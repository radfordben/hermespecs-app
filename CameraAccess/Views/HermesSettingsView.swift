/*
 * Hermes Settings View
 * Configure Hermes Agent connection settings
 */

import SwiftUI

struct HermesSettingsView: View {
    @ObservedObject private var hermesService = HermesService.shared
    @ObservedObject private var router = HermesCommandRouter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var serverHost: String = ""
    @State private var serverPort: String = ""
    @State private var apiToken: String = ""
    @State private var useSecureConnection: Bool = false
    @State private var showToken: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    @State private var showResetConfirmation: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Connection Status
                Section(header: Text("hermes.settings.status".localized)) {
                    HStack {
                        ConnectionStatusIndicator(state: hermesService.connectionState)
                        Spacer()
                        if hermesService.connectionState.isConnected {
                            Button("hermes.settings.disconnect".localized) {
                                hermesService.disconnect()
                            }
                            .foregroundColor(.red)
                        } else {
                            Button("hermes.settings.connect".localized) {
                                saveAndConnect()
                            }
                            .disabled(serverHost.isEmpty)
                        }
                    }

                    if case .error(let message) = hermesService.connectionState {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // MARK: - Server Configuration
                Section(header: Text("hermes.settings.server".localized)) {
                    TextField("hermes.settings.host".localized, text: $serverHost)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)

                    TextField("hermes.settings.port".localized, text: $serverPort)
                        .keyboardType(.numberPad)

                    Toggle("hermes.settings.secure".localized, isOn: $useSecureConnection)
                }

                // MARK: - Authentication
                Section(header: Text("hermes.settings.auth".localized)) {
                    HStack {
                        if showToken {
                            TextField("hermes.settings.token".localized, text: $apiToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("hermes.settings.token".localized, text: $apiToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }

                        Button(action: { showToken.toggle() }) {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }

                    if !apiToken.isEmpty {
                        Button("hermes.settings.clear_token".localized) {
                            apiToken = ""
                        }
                        .foregroundColor(.red)
                    }
                }

                // MARK: - Test Connection
                Section {
                    Button(action: testConnection) {
                        HStack {
                            Text("hermes.settings.test".localized)
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(serverHost.isEmpty || isTestingConnection)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(testSuccess ? .green : .red)
                    }
                }

                // MARK: - Session Info
                Section(header: Text("hermes.settings.session".localized)) {
                    HStack {
                        Text("hermes.settings.session_id".localized)
                        Spacer()
                        Text(hermesService.currentSessionId.prefix(8))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("hermes.settings.device_id".localized)
                        Spacer()
                        Text(hermesService.deviceId)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Button("hermes.settings.reset_session".localized) {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.orange)
                }

                // MARK: - Recent Activity
                if !router.recentToolCalls.isEmpty {
                    Section(header: Text("hermes.settings.recent_activity".localized)) {
                        ForEach(router.recentToolCalls.prefix(5), id: \.tool) { toolCall in
                            HStack {
                                Image(systemName: "hammer.fill")
                                    .foregroundColor(.purple)
                                Text(toolCall.tool)
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                }

                // MARK: - About
                Section(header: Text("hermes.settings.about".localized)) {
                    HStack {
                        Text("hermes.settings.version".localized)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }

                    Link(destination: URL(string: "https://github.com/radfordben/hermes-visionclaw")!) {
                        HStack {
                            Text("hermes.settings.github".localized)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("hermes.settings.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("general.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("general.save".localized) {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
            .alert("hermes.settings.reset_confirm".localized, isPresented: $showResetConfirmation) {
                Button("general.cancel".localized, role: .cancel) {}
                Button("general.reset".localized, role: .destructive) {
                    resetSession()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func loadSettings() {
        serverHost = hermesService.serverHost
        serverPort = String(hermesService.serverPort)
        useSecureConnection = hermesService.useSecureConnection
        apiToken = hermesService.loadAPIToken() ?? ""
    }

    private func saveSettings() {
        hermesService.serverHost = serverHost
        hermesService.serverPort = Int(serverPort) ?? 8787
        hermesService.useSecureConnection = useSecureConnection
        hermesService.saveSettings()

        if !apiToken.isEmpty {
            hermesService.saveAPIToken(apiToken)
        } else {
            hermesService.saveAPIToken("")
        }
    }

    private func saveAndConnect() {
        saveSettings()
        hermesService.connect()
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        // Save current settings temporarily
        let originalHost = hermesService.serverHost
        let originalPort = hermesService.serverPort
        let originalSecure = hermesService.useSecureConnection

        hermesService.serverHost = serverHost
        hermesService.serverPort = Int(serverPort) ?? 8787
        hermesService.useSecureConnection = useSecureConnection

        // Attempt connection
        hermesService.connect()

        // Wait and check status
        Task {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)

            await MainActor.run {
                isTestingConnection = false

                if hermesService.connectionState.isConnected {
                    testResult = "hermes.settings.test_success".localized
                    testSuccess = true
                } else {
                    testResult = "hermes.settings.test_failed".localized
                    testSuccess = false
                }

                // Restore original settings if not connected
                if !hermesService.connectionState.isConnected {
                    hermesService.disconnect()
                    hermesService.serverHost = originalHost
                    hermesService.serverPort = originalPort
                    hermesService.useSecureConnection = originalSecure
                }
            }
        }
    }

    private func resetSession() {
        let newSessionId = UUID().uuidString
        UserDefaults.standard.set(newSessionId, forKey: "hermes_session_id")
        hermesService.currentSessionId = newSessionId
    }
}

// MARK: - Connection Status Indicator

struct ConnectionStatusIndicator: View {
    let state: HermesConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .authenticating:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "hermes.status.connected".localized
        case .connecting:
            return "hermes.status.connecting".localized
        case .authenticating:
            return "hermes.status.authenticating".localized
        case .disconnected:
            return "hermes.status.disconnected".localized
        case .error:
            return "hermes.status.error".localized
        }
    }
}

// MARK: - Preview

struct HermesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HermesSettingsView()
    }
}
