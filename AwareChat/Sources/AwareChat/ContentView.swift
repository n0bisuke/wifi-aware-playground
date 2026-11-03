import DeviceDiscoveryUI
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
}

private struct ChatScreen: View {
    @State private var session = ChatSession()
    @State private var role: Role = .host
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                controls
                messageList
                composer
            }
            .padding()
            .navigationTitle("AwareChat")
        }
        .task {
            await session.observePairedDevices()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Role", selection: $role) {
                ForEach(Role.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(session.isRunning)

            pairingControl

            Text("Paired: \(pairedDeviceNames)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button(session.isRunning ? "Stop" : "Start", action: toggleSession)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isRunning && session.pairedDevices.isEmpty)

                Text(statusText)
                    .font(.footnote)
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

    private var messageList: some View {
        List(session.messages) { message in
            Text(message.text)
                .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        }
        .listStyle(.plain)
    }

    private var composer: some View {
        HStack {
            TextField("Message", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendDraft)

            Button("Send", action: sendDraft)
                .disabled(session.status != .connected || trimmedDraft.isEmpty)
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case .connected: "Connected"
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

    private func sendDraft() {
        let text = trimmedDraft
        guard session.status == .connected, !text.isEmpty else { return }
        draft = ""
        Task { await session.send(text) }
    }
}
