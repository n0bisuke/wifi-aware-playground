import Foundation
import Network
import Observation
import UIKit
import WiFiAware

/// Must match the key declared under `WiFiAwareServices` in Info.plist.
let chatServiceName = "_awarechat._tcp"

extension WAPublishableService {
    static var chatService: WAPublishableService {
        allServices[chatServiceName]!
    }
}

extension WASubscribableService {
    static var chatService: WASubscribableService {
        allServices[chatServiceName]!
    }
}

typealias ChatConnection = NetworkConnection<TLV>

/// The TLV type of each message on the connection.
private enum WireType: Int {
    case text = 1
    case photo = 2
    case draw = 3
    case speedStart = 4
    case speedChunk = 5
    case speedResult = 6
    case heartbeat = 7
}

private enum DrawEvent: Codable {
    case point(stroke: UUID, x: Double, y: Double)
    case clear
}

private struct SpeedStart: Codable {
    let totalBytes: Int
}

private struct SpeedResult: Codable {
    let bytes: Int
    let seconds: Double
}

struct ChatMessage: Identifiable {
    enum Content {
        case text(String)
        case photo(UIImage, byteCount: Int)
    }

    let id = UUID()
    let content: Content
    let isMine: Bool
}

struct Stroke: Identifiable {
    let id: UUID
    let isMine: Bool
    var points: [CGPoint]
}

enum SpeedTestState: Equatable {
    case idle
    case sending
    case receiving(receivedBytes: Int, totalBytes: Int)
    case finished(bytes: Int, seconds: Double, sentByMe: Bool)
}

/// A snapshot of the Wi-Fi Aware path, as reported by the system.
struct LinkStats: Equatable {
    /// Rough bands derived from signal strength. The thresholds are uncalibrated,
    /// and Wi-Fi Aware does not report distance, so this is not a measurement.
    enum Proximity: String {
        case veryClose = "すぐ近く"
        case nearby = "近く"
        case far = "離れている"
    }

    let signalStrength: Double?
    let capacityRatio: Double?
    let transmitLatency: Duration?
    let activeDuration: Duration

    init(path: WAPath) {
        signalStrength = path.performance.signalStrength
        capacityRatio = path.performance.throughputCapacityRatio
        transmitLatency = path.performance.transmitLatency[.bestEffort]?.average
        activeDuration = path.durationActive
    }

    var proximity: Proximity? {
        guard let signalStrength else { return nil }
        switch signalStrength {
        case 0.7...: return .veryClose
        case 0.4...: return .nearby
        default: return .far
        }
    }
}

@MainActor
@Observable
final class ChatSession {
    enum Status: Equatable {
        case idle
        case hosting
        case searching
        case connecting
        case connected
        case failed(String)
    }

    private struct Outgoing: Sendable {
        let type: Int
        let data: Data
    }

    private static let speedChunkSize = 1 << 20
    private static let speedChunkCount = 64
    /// Idle Wi-Fi Aware connections close after an undocumented few minutes.
    private static let heartbeatInterval: Duration = .seconds(10)
    /// Long enough to tolerate several missed heartbeats before reconnecting.
    private static let peerSilenceLimit: Duration = .seconds(45)
    private static let retryDelay: Duration = .seconds(3)

    private(set) var status: Status = .idle
    private(set) var messages: [ChatMessage] = []
    private(set) var pairedDevices: [WAPairedDevice] = []
    private(set) var linkStats: LinkStats?
    private(set) var strokes: [Stroke] = []
    private(set) var speedTest: SpeedTestState = .idle
    /// The most recent disconnection or failure, kept on screen to diagnose drops.
    private(set) var lastIssue: String?

    private var lastReceivedAt: ContinuousClock.Instant = .now
    private var connectedAt: ContinuousClock.Instant?
    private var connection: ChatConnection?
    private var runTask: Task<Void, Never>?
    private var outgoing: AsyncStream<Outgoing>.Continuation?
    private var speedTestStart: ContinuousClock.Instant?

    var isRunning: Bool { runTask != nil }

    /// Keeps `pairedDevices` current. Runs until the calling task is cancelled.
    func observePairedDevices() async {
        do {
            for try await devices in WAPairedDevice.allDevices {
                pairedDevices = devices.values.sorted { $0.id < $1.id }
            }
        } catch {
            status = .failed("Paired devices: \(error.localizedDescription)")
        }
    }

    /// Publisher role: advertise the service and accept paired devices.
    func startHosting() {
        start(initialStatus: .hosting) { session in
            try await NetworkListener(
                for: .wifiAware(.connecting(to: .chatService, from: .allPairedDevices)),
                using: .parameters { Self.makeProtocolStack() }
            )
            .onStateUpdate { _, state in
                if case .failed(let error) = state {
                    print("Listener failed: \(Self.describe(error))")
                }
            }
            .run { connection in
                // The listener keeps running, so the host can accept a reconnection.
                await session.communicate(over: connection, statusAfterDisconnect: .hosting)
            }
        }
    }

    /// Subscriber role: find the first paired device publishing the service and connect.
    func startJoining() {
        start(initialStatus: .searching) { session in
            let browser = NetworkBrowser(
                for: .wifiAware(.connecting(to: .allPairedDevices, from: .chatService))
            )
            .onStateUpdate { _, state in
                if case .failed(let error) = state {
                    print("Browser failed: \(Self.describe(error))")
                }
            }

            let endpoint = try await browser.run { endpoints in
                if let first = endpoints.first {
                    return .finish(first)
                }
                return .continue
            }

            session.status = .connecting
            let connection = ChatConnection(
                to: endpoint,
                using: .parameters { Self.makeProtocolStack() }
            )
            await session.communicate(over: connection, statusAfterDisconnect: .searching)
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        connection = nil
        outgoing = nil
        linkStats = nil
        speedTest = .idle
        status = .idle
    }

    // MARK: - Sending

    func send(_ text: String) {
        enqueue(.text, Data(text.utf8))
        messages.append(ChatMessage(content: .text(text), isMine: true))
    }

    func sendPhoto(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        enqueue(.photo, data)
        messages.append(ChatMessage(content: .photo(image, byteCount: data.count), isMine: true))
    }

    /// Adds a point in normalized (0...1) coordinates to a local stroke and shares it.
    func addPoint(_ point: CGPoint, toStroke id: UUID) {
        append(point, toStroke: id, isMine: true)
        enqueueDraw(.point(stroke: id, x: point.x, y: point.y))
    }

    func clearDrawing() {
        strokes = []
        enqueueDraw(.clear)
    }

    /// The receiver times the transfer, so the result excludes local send buffering.
    func startSpeedTest() {
        switch speedTest {
        case .sending, .receiving:
            return
        case .idle, .finished:
            break
        }
        speedTest = .sending
        let totalBytes = Self.speedChunkSize * Self.speedChunkCount
        guard let start = try? JSONEncoder().encode(SpeedStart(totalBytes: totalBytes)) else { return }
        enqueue(.speedStart, start)
        let chunk = Data(count: Self.speedChunkSize)
        for _ in 0..<Self.speedChunkCount {
            enqueue(.speedChunk, chunk)
        }
    }

    private func enqueue(_ type: WireType, _ data: Data) {
        outgoing?.yield(Outgoing(type: type.rawValue, data: data))
    }

    private func enqueueDraw(_ event: DrawEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        enqueue(.draw, data)
    }

    // MARK: - Receiving

    private func handleMessage(type: Int, content: Data) {
        switch WireType(rawValue: type) {
        case .text:
            messages.append(ChatMessage(content: .text(String(decoding: content, as: UTF8.self)), isMine: false))
        case .photo:
            if let image = UIImage(data: content) {
                messages.append(ChatMessage(content: .photo(image, byteCount: content.count), isMine: false))
            }
        case .draw:
            guard let event = try? JSONDecoder().decode(DrawEvent.self, from: content) else { return }
            switch event {
            case .point(let stroke, let x, let y):
                append(CGPoint(x: x, y: y), toStroke: stroke, isMine: false)
            case .clear:
                strokes = []
            }
        case .speedStart:
            guard let start = try? JSONDecoder().decode(SpeedStart.self, from: content) else { return }
            speedTestStart = .now
            speedTest = .receiving(receivedBytes: 0, totalBytes: start.totalBytes)
        case .speedChunk:
            receiveSpeedChunk(byteCount: content.count)
        case .speedResult:
            guard let result = try? JSONDecoder().decode(SpeedResult.self, from: content) else { return }
            speedTest = .finished(bytes: result.bytes, seconds: result.seconds, sentByMe: true)
        case .heartbeat, nil:
            break
        }
    }

    private func receiveSpeedChunk(byteCount: Int) {
        guard case .receiving(let received, let total) = speedTest,
              let speedTestStart else { return }
        let updated = received + byteCount
        guard updated >= total else {
            speedTest = .receiving(receivedBytes: updated, totalBytes: total)
            return
        }

        let elapsed = speedTestStart.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        speedTest = .finished(bytes: updated, seconds: seconds, sentByMe: false)
        if let data = try? JSONEncoder().encode(SpeedResult(bytes: updated, seconds: seconds)) {
            enqueue(.speedResult, data)
        }
    }

    private func append(_ point: CGPoint, toStroke id: UUID, isMine: Bool) {
        if let index = strokes.lastIndex(where: { $0.id == id }) {
            strokes[index].points.append(point)
        } else {
            strokes.append(Stroke(id: id, isMine: isMine, points: [point]))
        }
    }

    // MARK: - Connection lifetime

    private func start(
        initialStatus: Status,
        operation: @escaping @MainActor (ChatSession) async throws -> Void
    ) {
        stop()
        lastIssue = nil
        // Retries until stopped, so a dropped link reconnects without user action.
        runTask = Task {
            while !Task.isCancelled {
                self.status = initialStatus
                do {
                    try await operation(self)
                } catch {
                    if Task.isCancelled || error is CancellationError { return }
                    self.status = .failed(Self.describe(error))
                    self.recordIssue(Self.describe(error))
                }
                try? await Task.sleep(for: Self.retryDelay)
            }
        }
    }

    private func recordIssue(_ text: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        if let connectedAt {
            let seconds = connectedAt.duration(to: .now).components.seconds
            lastIssue = "\(time) 接続\(seconds)秒で切断: \(text)"
        } else {
            lastIssue = "\(time) \(text)"
        }
        connectedAt = nil
    }

    /// Receives messages until the connection ends. `messages` also starts the connection.
    private func communicate(
        over connection: ChatConnection,
        statusAfterDisconnect: Status
    ) async {
        self.connection = connection
        connection.onStateUpdate { [weak self] connection, state in
            guard let self, self.connection === connection else { return }
            switch state {
            case .ready:
                self.connectedAt = .now
                self.lastReceivedAt = .now
                self.status = .connected
            case .failed(let error), .waiting(let error):
                self.status = .failed(Self.describe(error))
                self.recordIssue(Self.describe(error))
            default:
                break
            }
        }

        // One queue keeps stroke points and speed test chunks in the order they were made.
        let (stream, continuation) = AsyncStream.makeStream(of: Outgoing.self)
        outgoing = continuation
        let sendTask = Task { await runSendQueue(stream, on: connection) }
        let statsTask = Task { await monitorLink(of: connection) }
        let heartbeatTask = Task { await sendHeartbeats() }
        let receiveTask = Task { await receiveMessages(from: connection) }
        let watchdogTask = Task { await watchPeerSilence(cancelling: receiveTask) }
        defer {
            continuation.finish()
            sendTask.cancel()
            statsTask.cancel()
            heartbeatTask.cancel()
            watchdogTask.cancel()
        }

        await withTaskCancellationHandler {
            await receiveTask.value
        } onCancel: {
            receiveTask.cancel()
        }

        if self.connection === connection {
            self.connection = nil
            outgoing = nil
            linkStats = nil
            speedTest = .idle
            if connectedAt != nil {
                recordIssue("相手との接続が終了")
            }
            status = statusAfterDisconnect
        }
    }

    private func receiveMessages(from connection: ChatConnection) async {
        do {
            var partial = Data()
            for try await (content, metadata) in connection.messages {
                lastReceivedAt = .now
                partial.append(content)
                guard metadata.isComplete else { continue }
                handleMessage(type: metadata.type, content: partial)
                partial = Data()
            }
        } catch {
            if !Task.isCancelled, self.connection === connection {
                recordIssue(Self.describe(error))
            }
        }
    }

    private func sendHeartbeats() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.heartbeatInterval)
            if status == .connected {
                enqueue(.heartbeat, Data())
            }
        }
    }

    /// A stalled link can stay open without erroring, so silence also ends the connection.
    private func watchPeerSilence(cancelling receiveTask: Task<Void, Never>) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if status == .connected, lastReceivedAt.duration(to: .now) > Self.peerSilenceLimit {
                recordIssue("相手からの通信が途絶えた")
                receiveTask.cancel()
                return
            }
        }
    }

    private func runSendQueue(_ stream: AsyncStream<Outgoing>, on connection: ChatConnection) async {
        do {
            for await message in stream {
                try await connection.send(message.data, type: message.type)
            }
        } catch {
            if !Task.isCancelled, self.connection === connection {
                status = .failed("Send: \(Self.describe(error))")
            }
        }
    }

    /// Refreshes `linkStats` every two seconds while this connection is the current one.
    private func monitorLink(of connection: ChatConnection) async {
        while !Task.isCancelled, self.connection === connection {
            if connection.state == .ready,
               let path = try? await connection.currentPath?.wifiAware,
               self.connection === connection {
                linkStats = LinkStats(path: path)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Wi-Fi Aware authenticates and encrypts the link, so no TLS identity is configured.
    /// A bare `TLS()` under Coder failed the handshake with errSSLPeerInternalError (-9838).
    private nonisolated static func makeProtocolStack() -> TLV {
        TLV {
            TCP()
        }
    }

    private nonisolated static func describe(_ error: any Error) -> String {
        if let nwError = error as? NWError, let wifiAwareError = nwError.wifiAware {
            // The case name identifies causes such as connectionIdleTimeout.
            let caseName = String(describing: wifiAwareError).prefix { $0 != "(" }
            return "\(caseName): \(wifiAwareError.localizedDescription)"
        }
        return error.localizedDescription
    }
}
