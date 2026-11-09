import DeviceDiscoveryUI
import PhotosUI
import SwiftUI
import WiFiAware

struct ContentView: View {
    var body: some View {
        if WACapabilities.supportedFeatures.contains(.wifiAware) {
            ChatScreen()
        } else {
            ContentUnavailableView(
                "Wi-Fi Aware Unavailable",
                systemImage: "wifi.slash",
                description: Text("This device does not support Wi-Fi Aware.")
            )
        }
    }
}

private enum Role: String, CaseIterable, Identifiable {
    case host = "Host"
    case join = "Join"

    var id: Self { self }

    var color: Color {
        switch self {
        case .host: .orange
        case .join: .blue
        }
    }

    var systemImage: String {
        switch self {
        case .host: "antenna.radiowaves.left.and.right"
        case .join: "magnifyingglass"
        }
    }

    var summary: String {
        switch self {
        case .host: "相手からの接続を待ち受けます"
        case .join: "Hostを探して接続します"
        }
    }
}

private enum Demo: String, CaseIterable, Identifiable {
    case chat = "チャット"
    case draw = "お絵描き"
    case speed = "速度"

    var id: Self { self }
}

private struct RoleBanner: View {
    let role: Role

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: role.systemImage)
                .font(.title2)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(role.rawValue)
                    .font(.headline)
                Text(role.summary)
                    .font(.footnote)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(role.color, in: .rect(cornerRadius: 12))
    }
}

private struct LinkStatsPanel: View {
    let stats: LinkStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(proximityText, systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                Spacer()
                Text(percent(stats.signalStrength))
                    .font(.subheadline.bold().monospacedDigit())
            }

            ProgressView(value: stats.signalStrength ?? 0)

            Text("距離は電波強度からの目安です。実測値ではありません。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("余力 \(percent(stats.capacityRatio))")
                Text("遅延 \(milliseconds(stats.transmitLatency))")
                Text("接続 \(stats.activeDuration.components.seconds) 秒")
            }
            .font(.caption.monospacedDigit())
        }
        .padding(10)
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private var proximityText: String {
        stats.proximity.map { "距離の目安: \($0.rawValue)" } ?? "距離の目安: 不明"
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded())) %"
    }

    private func milliseconds(_ duration: Duration?) -> String {
        guard let duration else { return "—" }
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        return "\(value.formatted(.number.precision(.fractionLength(1)))) ms"
    }
}

private struct ChatDemo: View {
    let session: ChatSession

    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isSendingPhoto = false

    var body: some View {
        // PhotosPicker's label closure is Sendable, so it captures a value, not the state.
        let photoIcon = isSendingPhoto ? "hourglass" : "photo"

        VStack(spacing: 8) {
            List(session.messages) { message in
                messageView(message)
                    .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: photoIcon)
                }
                .disabled(session.status != .connected || isSendingPhoto)

                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendDraft)

                Button("Send", action: sendDraft)
                    .disabled(session.status != .connected || trimmedDraft.isEmpty)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            isSendingPhoto = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    session.sendPhoto(data)
                }
                photoItem = nil
                isSendingPhoto = false
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.content {
        case .text(let text):
            Text(text)
        case .photo(let image, let byteCount):
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(.rect(cornerRadius: 8))
                Text(Int64(byteCount).formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendDraft() {
        let text = trimmedDraft
        guard session.status == .connected, !text.isEmpty else { return }
        draft = ""
        session.send(text)
    }
}

private struct DrawDemo: View {
    let session: ChatSession
    let myColor: Color
    let peerColor: Color

    @State private var currentStroke: UUID?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                Canvas { context, size in
                    for stroke in session.strokes {
                        draw(stroke, in: &context, size: size)
                    }
                }
                .background(.background, in: .rect(cornerRadius: 12))
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let id = currentStroke ?? UUID()
                            currentStroke = id
                            session.addPoint(normalized(value.location, in: geometry.size), toStroke: id)
                        }
                        .onEnded { _ in
                            currentStroke = nil
                        }
                )
            }

            HStack {
                Label("自分", systemImage: "circle.fill").foregroundStyle(myColor)
                Label("相手", systemImage: "circle.fill").foregroundStyle(peerColor)
                Spacer()
                Button("消す", role: .destructive, action: session.clearDrawing)
            }
            .font(.footnote)
        }
    }

    private func draw(_ stroke: Stroke, in context: inout GraphicsContext, size: CGSize) {
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        path.addLine(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(stroke.isMine ? myColor : peerColor),
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        )
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x / max(size.width, 1), 0), 1),
            y: min(max(point.y / max(size.height, 1), 0), 1)
        )
    }
}

private struct SpeedDemo: View {
    let session: ChatSession

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            switch session.speedTest {
            case .idle:
                Text("相手のiPhoneへデータを送って、受信側で速度を測ります。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .sending:
                ProgressView("送信中…")
            case .receiving(let received, let total):
                ProgressView("受信中…", value: Double(received), total: Double(total))
            case .finished(let bytes, let seconds, let sentByMe):
                let megabytesPerSecond = Double(bytes) / 1_000_000 / max(seconds, 0.001)
                Text("\(megabytesPerSecond.formatted(.number.precision(.fractionLength(1)))) MB/s")
                    .font(.largeTitle.bold().monospacedDigit())
                Text("\((megabytesPerSecond * 8).formatted(.number.precision(.fractionLength(0)))) Mbps")
                    .foregroundStyle(.secondary)
                Text("\(Int64(bytes).formatted(.byteCount(style: .file))) を\(seconds.formatted(.number.precision(.fractionLength(2)))) 秒で\(sentByMe ? "送信" : "受信")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("64 MiB を送って測る", action: session.startSpeedTest)
                .buttonStyle(.borderedProminent)
                .disabled(session.status != .connected || isTesting)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isTesting: Bool {
        switch session.speedTest {
        case .sending, .receiving: true
        case .idle, .finished: false
        }
    }
}

private struct ChatScreen: View {
    @State private var session = ChatSession()
    @State private var role: Role = .host
    @State private var demo: Demo = .chat

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                controls
                if let stats = session.linkStats {
                    LinkStatsPanel(stats: stats)
                }
                Picker("Demo", selection: $demo) {
                    ForEach(Demo.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                demoView
            }
            .padding()
            .background(role.color.opacity(0.08))
            .tint(role.color)
            .navigationTitle("AwareChat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await session.observePairedDevices()
        }
        // Screen lock suspends the app, and suspension closes the Wi-Fi Aware connection.
        .onChange(of: session.isRunning) { _, isRunning in
            UIApplication.shared.isIdleTimerDisabled = isRunning
        }
    }

    @ViewBuilder
    private var demoView: some View {
        switch demo {
        case .chat:
            ChatDemo(session: session)
        case .draw:
            DrawDemo(session: session, myColor: role.color, peerColor: peerRole.color)
        case .speed:
            SpeedDemo(session: session)
        }
    }

    private var peerRole: Role {
        role == .host ? .join : .host
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Setup controls are hidden while connected to leave room for the demos.
            if session.status != .connected {
                Picker("Role", selection: $role) {
                    ForEach(Role.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(session.isRunning)

                RoleBanner(role: role)

                pairingControl

                Text("Paired: \(pairedDeviceNames)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(session.isRunning ? "Stop" : "Start", action: toggleSession)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isRunning && session.pairedDevices.isEmpty)

                Text(statusText)
                    .font(.footnote)
            }

            if let issue = session.lastIssue {
                Text("前回: \(issue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Pairing is initiated from the Join device; the Host device accepts it.
    @ViewBuilder
    private var pairingControl: some View {
        switch role {
        case .host:
            DevicePairingView(.wifiAware(.connecting(to: .chatService, from: .userSpecifiedDevices))) {
                Label("Allow Pairing", systemImage: "plus")
            } fallback: {
                Label("Pairing Unavailable", systemImage: "xmark.circle")
            }
        case .join:
            DevicePicker(.wifiAware(.connecting(to: .userSpecifiedDevices, from: .chatService))) { endpoint in
                print("Paired endpoint: \(endpoint)")
            } label: {
                Label("Add Device", systemImage: "plus")
            } fallback: {
                Label("Pairing Unavailable", systemImage: "xmark.circle")
            }
        }
    }

    private var pairedDeviceNames: String {
        guard !session.pairedDevices.isEmpty else { return "none" }
        return session.pairedDevices
            .map { $0.name ?? $0.pairingInfo?.pairingName ?? "Unknown" }
            .joined(separator: ", ")
    }

    private var statusText: String {
        switch session.status {
        case .idle: "Idle"
        case .hosting: "Waiting for a connection…"
        case .searching: "Searching…"
        case .connecting: "Connecting…"
        case .connected: "Connected (\(role.rawValue))"
        case .failed(let reason): "Error: \(reason)"
        }
    }

    private func toggleSession() {
        if session.isRunning {
            session.stop()
        } else if role == .host {
            session.startHosting()
        } else {
            session.startJoining()
        }
    }
}
