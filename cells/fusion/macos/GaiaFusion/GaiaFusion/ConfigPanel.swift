import AppKit
import SwiftUI
import Foundation

struct ConfigPanel: View {
    @Binding var isPresented: Bool

    @State private var natsURL = UserDefaults.standard.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
    @State private var natsSubjects = UserDefaults.standard.string(forKey: "fusion_nats_subject") ?? "gaiaftcl.fusion.cell.status.v1,gaiaftcl.fusion.mesh_mooring.v1,gaiaftcl.cell.id,gaiaftcl.cell.id"
    @State private var heartbeatSeconds = UserDefaults.standard.integer(forKey: "fusion_heartbeat_seconds").nonZeroOrDefault(15)
    @State private var meshHealEnabled = UserDefaults.standard.bool(forKey: "fusion_mesh_heal_enabled")

    @State private var uiPort = String(UserDefaults.standard.integer(forKey: "fusion_ui_port"))
    @State private var devMode = UserDefaults.standard.bool(forKey: "fusion_dev_mode")

    @State private var sshKeyPath = UserDefaults.standard.string(forKey: "fusion_ssh_key_path") ?? ""
    @State private var sshUser = UserDefaults.standard.string(forKey: "fusion_ssh_user") ?? "root"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GaiaFusion Preferences")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Mesh Connection")
                    .font(.headline)

                HStack {
                    Text("NATS URL")
                        .frame(width: 150, alignment: .leading)
                    TextField("nats://127.0.0.1:4222", text: $natsURL)
                }
                HStack {
                    Text("NATS Subject(s)")
                        .frame(width: 150, alignment: .leading)
                    TextField("gaiaftcl.fusion.cell.status.v1,gaiaftcl.fusion.mesh_mooring.v1", text: $natsSubjects)
                }
                HStack {
                    Text("Heartbeat (sec)")
                        .frame(width: 150, alignment: .leading)
                    Stepper(value: $heartbeatSeconds, in: 5...120) {
                        Text("\(heartbeatSeconds)")
                    }
                }
                Toggle("Mesh heal enabled", isOn: $meshHealEnabled)
                Text(
                    "When enabled and an SSH key is set, offline fleet cells receive a non-interactive restart script for :8803 (10 min cooldown per cell). MCP loopback 127.0.0.1:8803 is started by the app and proxies to the sidecar guest unless GAIAFUSION_MCP_LOOPBACK_DISABLE=1."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            VStack(alignment: .leading, spacing: 10) {
                Text("Display")
                    .font(.headline)
                HStack {
                    Text("UI Port")
                        .frame(width: 150, alignment: .leading)
                    TextField("8910", text: $uiPort)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Dev mode (proxy to :3000)", isOn: $devMode)
            }
            .padding(12)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            VStack(alignment: .leading, spacing: 10) {
                Text("SSH")
                    .font(.headline)
                HStack {
                    Text("Key path")
                        .frame(width: 150, alignment: .leading)
                    Text(maskedPath(sshKeyPath))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Pick") {
                        pickSSHKey()
                    }
                    if !sshKeyPath.isEmpty {
                        Button("Clear") {
                            sshKeyPath = ""
                        }
                    }
                }
                HStack {
                    Text("User")
                        .frame(width: 150, alignment: .leading)
                    TextField("root", text: $sshUser)
                }
            }
            .padding(12)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            VStack(alignment: .leading, spacing: 8) {
                Text("Physics (read-only)")
                    .font(.headline)
                Text("vQbit in the status bar is a local mesh health ratio, not Arango vqbit_measurements unless gateway-ingested.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Quorum threshold: 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Save") {
                    save()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private func maskedPath(_ path: String) -> String {
        guard !path.isEmpty else {
            return "Not configured"
        }
        let keyName = URL(fileURLWithPath: path).lastPathComponent
        return "•••/\(keyName)"
    }

    private func pickSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Key"
        if panel.runModal() == .OK, let url = panel.url {
            sshKeyPath = url.path
        }
    }

    private func save() {
        UserDefaults.standard.setValue(natsURL, forKey: "fusion_nats_url")
        UserDefaults.standard.setValue(natsSubjects, forKey: "fusion_nats_subject")
        UserDefaults.standard.setValue(heartbeatSeconds, forKey: "fusion_heartbeat_seconds")
        UserDefaults.standard.setValue(meshHealEnabled, forKey: "fusion_mesh_heal_enabled")
        UserDefaults.standard.setValue(Int(uiPort), forKey: "fusion_ui_port")
        UserDefaults.standard.setValue(devMode, forKey: "fusion_dev_mode")
        UserDefaults.standard.setValue(sshKeyPath, forKey: "fusion_ssh_key_path")
        UserDefaults.standard.setValue(sshUser, forKey: "fusion_ssh_user")
    }
}

private extension Int {
    func nonZeroOrDefault(_ fallback: Int) -> Int {
        guard self > 0 else { return fallback }
        return self
    }
}
