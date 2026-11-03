import Foundation
import Network
import Observation
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

/// The payload exchanged between the two devices.
struct ChatPayload: Codable, Sendable {
    let text: String
}

typealias ChatProtocol = Coder<ChatPayload, ChatPayload, NetworkJSONCoder>
typealias ChatConnection = NetworkConnection<ChatProtocol>

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isMine: Bool
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

    private(set) var status: Status = .idle
    private(set) var messages: [ChatMessage] = []
    private(set) var pairedDevices: [WAPairedDevice] = []

    private var connection: ChatConnection?
    private var runTask: Task<Void, Never>?

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
            await session.communicate(over: connection, statusAfterDisconnect: .idle)
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        connection = nil
        status = .idle
    }

    func send(_ text: String) async {
        guard let connection else { return }
        do {
            try await connection.send(ChatPayload(text: text))
            messages.append(ChatMessage(text: text, isMine: true))
        } catch {
            status = .failed("Send: \(Self.describe(error))")
        }
    }

    private func start(
        initialStatus: Status,
        operation: @escaping @MainActor (ChatSession) async throws -> Void
    ) {
        stop()
        status = initialStatus
        runTask = Task {
            do {
                try await operation(self)
            } catch {
                if !Task.isCancelled, !(error is CancellationError) {
                    self.status = .failed(Self.describe(error))
                }
            }
            // A cancelled task was stopped or replaced; the new state is not ours to touch.
            if !Task.isCancelled {
                self.runTask = nil
            }
        }
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
                self.status = .connected
            case .failed(let error), .waiting(let error):
                self.status = .failed(Self.describe(error))
            default:
                break
            }
        }

        do {
            for try await (payload, _) in connection.messages {
                messages.append(ChatMessage(text: payload.text, isMine: false))
            }
        } catch {
            if !Task.isCancelled, self.connection === connection {
                status = .failed(Self.describe(error))
            }
        }

        if self.connection === connection {
            self.connection = nil
            if status == .connected {
                status = statusAfterDisconnect
            }
        }
    }

    /// TLS follows Apple's `_tcp` Wi-Fi Aware example; Coder adds message framing and JSON.
    private nonisolated static func makeProtocolStack() -> ChatProtocol {
        Coder(ChatPayload.self, using: NetworkJSONCoder()) {
            TLS()
        }
    }

    private nonisolated static func describe(_ error: any Error) -> String {
        if let nwError = error as? NWError, let wifiAwareError = nwError.wifiAware {
            return wifiAwareError.localizedDescription
        }
        return error.localizedDescription
    }
}
