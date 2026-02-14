import SwiftUI
import EventKit
import ActivityKit

struct SettingsView: View {
    @Environment(GatewayClient.self) private var gateway
    @Environment(CalendarManager.self) private var calendarManager
    
    @AppStorage("gatewayHost") private var host = "192.168.1.197"
    @AppStorage("gatewayPort") private var port = 18789
    @AppStorage("gatewayToken") private var token = ""
    @AppStorage("autoConnect") private var autoConnect = true
    
    @State private var showingToken = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Connection
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(gateway.isConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(gateway.isConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("18789", value: $port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        if showingToken {
                            TextField("Token", text: $token)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Token", text: $token)
                        }
                        Button {
                            showingToken.toggle()
                        } label: {
                            Image(systemName: showingToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Toggle("Auto-connect", isOn: $autoConnect)
                } header: {
                    Text("Gateway Connection")
                } footer: {
                    Text("Connect to the OpenClaw gateway running on your Mac mini.")
                }
                
                Section {
                    if gateway.isConnected {
                        Button("Disconnect", role: .destructive) {
                            gateway.disconnect()
                        }
                    } else {
                        Button("Connect") {
                            gateway.configure(host: host, port: port, token: token)
                            gateway.connect()
                        }
                        .disabled(host.isEmpty || token.isEmpty)
                    }
                    
                    if let error = gateway.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Live Activities
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "Enabled" : "Disabled")
                            .foregroundStyle(.secondary)
                    }
                    
                    if !ActivityAuthorizationInfo().areActivitiesEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live Activities are disabled.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Enable them in Settings → Frank → Live Activities")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Live Activities")
                } footer: {
                    Text("Show Frank's status on your Lock Screen and in the Dynamic Island.")
                }
                
                // Calendar
                Section {
                    HStack {
                        Text("Access")
                        Spacer()
                        Text(calendarStatusText)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Events Loaded")
                        Spacer()
                        Text("\(calendarManager.upcomingEvents.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar")
                }
                
                // About
                Section("About") {
                    infoRow("Version", "1.0.0")
                    infoRow("Agent", "Frank 🦞")
                    infoRow("Platform", "OpenClaw")
                    
                    if gateway.isConnected {
                        infoRow("Model", gateway.modelName)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private var calendarStatusText: String {
        switch calendarManager.authorizationStatus {
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Write Only"
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }
    
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
