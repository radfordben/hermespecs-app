/*
 * OpenClaw Settings View
 * 配置 OpenClaw Gateway 连接
 */

import SwiftUI

struct OpenClawSettingsView: View {
    @ObservedObject var nodeService = OpenClawNodeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var portText: String = ""
    @State private var token: String = ""
    @State private var showSaveSuccess = false

    var body: some View {
        NavigationView {
            Form {
                // Connection status
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(statusText)
                                .font(AppTypography.caption)
                                .foregroundColor(statusColor)
                        }
                    }

                    if nodeService.connectionState == .waitingForPairing {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("openclaw.pairing.hint".localized)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                } header: {
                    Text("OpenClaw")
                }

                // Gateway configuration
                Section {
                    HStack {
                        Text("Host")
                            .frame(width: 50, alignment: .leading)
                        TextField("127.0.0.1", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    HStack {
                        Text("Port")
                            .frame(width: 50, alignment: .leading)
                        TextField("18789", text: $portText)
                            .keyboardType(.numberPad)
                    }

                    SecureField("Gateway Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Gateway")
                } footer: {
                    Text("openclaw.gateway.help".localized)
                }

                // Actions
                Section {
                    if nodeService.connectionState == .connected {
                        Button(role: .destructive) {
                            nodeService.disconnect()
                        } label: {
                            HStack {
                                Image(systemName: "wifi.slash")
                                Text("openclaw.disconnect".localized)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button {
                            saveAndConnect()
                        } label: {
                            HStack {
                                Image(systemName: "wifi")
                                Text("openclaw.connect".localized)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(host.isEmpty)
                    }
                }

                // Info
                Section {
                    InfoRow(title: "Node ID", value: nodeService.connectionState == .connected ? "rayban-node" : "-")
                    InfoRow(title: "Commands", value: "camera.snap, device.status, device.info")
                } header: {
                    Text("openclaw.capabilities".localized)
                } footer: {
                    Text("openclaw.capabilities.desc".localized)
                }
            }
            .navigationTitle("OpenClaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                host = nodeService.gatewayHost
                portText = "\(nodeService.gatewayPort)"
                token = nodeService.loadGatewayToken() ?? ""
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch nodeService.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .waitingForPairing: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch nodeService.connectionState {
        case .connected: return "openclaw.status.connected".localized
        case .connecting: return "openclaw.status.connecting".localized
        case .waitingForPairing: return "openclaw.status.pairing".localized
        case .disconnected: return "openclaw.status.disconnected".localized
        case .error(let msg): return msg
        }
    }

    private func saveAndConnect() {
        nodeService.gatewayHost = host
        nodeService.gatewayPort = Int(portText) ?? 18789
        if !token.isEmpty {
            nodeService.saveGatewayToken(token)
        }
        nodeService.connect()
    }
}
