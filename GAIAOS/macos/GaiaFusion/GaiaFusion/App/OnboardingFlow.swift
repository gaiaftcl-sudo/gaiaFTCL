import SwiftUI
import Foundation

enum OnboardingStage: Int, CaseIterable {
    case welcome = 0
    case nats = 1
    case probe = 2
    case mooring = 3

    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .nats:
            "NATS Connection"
        case .probe:
            "Mesh Probe"
        case .mooring:
            "Mooring"
        }
    }
}

struct OnboardingFlow: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var stage: OnboardingStage = .welcome
    @State private var natsURL: String = UserDefaults.standard.string(forKey: "fusion_nats_url") ?? "nats://127.0.0.1:4222"
    @State private var probeCells: Int = 0
    @State private var probeBusy = false
    @State private var mooringBusy = false
    @State private var statusMessage: String = ""
    @State private var statusIsError = false
    @State private var natsTested = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("GaiaFusion Plasma Control")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Skip Onboarding") {
                    coordinator.skipOnboarding()
                }
                .keyboardShortcut(.escape, modifiers: [.command, .shift])
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(stage.title)
                .font(.headline)
                .foregroundStyle(.secondary)

            content

            Spacer()

            HStack {
                if stage != .welcome {
                    Button("Back") {
                        move(to: OnboardingStage(rawValue: stage.rawValue - 1) ?? .welcome)
                    }
                    .keyboardShortcut(.escape)
                }

                Spacer()

                statusTag

                Spacer()

                if stage == .mooring {
                    Button("Finish") {
                        Task {
                            await finishOnboarding()
                        }
                    }
                    .keyboardShortcut(.return)
                    .disabled(mooringBusy)
                } else {
                    Button(action: {
                        move(to: OnboardingStage(rawValue: stage.rawValue + 1) ?? .mooring)
                    }) {
                        Text("Next")
                    }
                    .disabled(nextDisabled)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(20)
        .onAppear {
            statusMessage = ""
        }
        .frame(minWidth: 700, minHeight: 620)
        .onChange(of: coordinator.meshManager.cells) { _, value in
            if stage == .probe {
                probeCells = value.filter { $0.active }.count
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch stage {
            case .welcome:
                welcomeContent
            case .nats:
                natsContent
            case .probe:
                probeContent
            case .mooring:
                mooringContent
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control your nine-cell sovereign mesh")
                .font(.system(.title3, design: .rounded))
            Text(
                "The macOS shell is now the cockpit. The WebView is the plasma core. " +
                "Next steps configure NATS, probe the mesh, then create mooring receipts."
            )
            .foregroundStyle(.secondary)
            Text("Use real live nodes only.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var natsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your NATS URL")
                .font(.system(.body, design: .monospaced))
            TextField("NATS URL", text: $natsURL)
                .textFieldStyle(.roundedBorder)
            Button("Test Connection") {
                Task {
                    let result = await coordinator.testNATSConnection(urlString: natsURL)
                    statusMessage = result.1
                    statusIsError = !result.0
                    natsTested = result.0
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(natsURL.isEmpty)
            statusLine
        }
    }

    private var probeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Probing all nine sovereign cells")
                .font(.system(.body, design: .monospaced))
            if probeBusy {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Probing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Active cells found: \(probeCells) / \(coordinator.meshManager.cells.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            List(coordinator.meshManager.cells, id: \.id) { cell in
                HStack {
                    Circle()
                        .fill(cell.active ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(cell.id)
                    Spacer()
                    Text("\(Int(cell.healthPercent))%")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 220)
        }
        .onAppear {
            runProbe()
        }
    }

    private var mooringContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Creating onboarding receipts")
                .font(.system(.body, design: .monospaced))
            Text("This writes cell_identity.json and mount receipts for the active mesh state.")
                .foregroundStyle(.secondary)
                .font(.caption)
            if mooringBusy {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Writing receipts...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(statusMessage)
                .foregroundStyle(statusIsError ? .red : .green)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 24)
            if !mooringBusy && !statusMessage.isEmpty {
                Text("State: \(statusMessage)")
                    .font(.caption2)
            }
        }
        .onAppear {
            if statusMessage.isEmpty {
                statusMessage = "Ready to generate MOORED receipts."
                statusIsError = false
            }
        }
    }

    private var statusLine: some View {
        Text(statusMessage)
            .foregroundStyle(statusIsError ? Color.red : Color.green)
            .font(.system(size: 11, design: .monospaced))
            .frame(minHeight: 16)
    }

    @ViewBuilder
    private var statusTag: some View {
        if !statusMessage.isEmpty {
            Text(statusMessage)
                .foregroundStyle(statusIsError ? Color.red : Color.green)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private var nextDisabled: Bool {
        switch stage {
        case .welcome:
            false
        case .nats:
            !natsTested
        case .probe:
            false
        case .mooring:
            false
        }
    }

    private func move(to next: OnboardingStage) {
        stage = next
        statusMessage = ""
        statusIsError = false
    }

    private func runProbe() {
        guard !probeBusy else {
            return
        }
        probeBusy = true
        Task {
            let cells = await coordinator.probeAllCellsNow()
            await MainActor.run {
                probeCells = cells.filter { $0.active }.count
                probeBusy = false
                statusMessage = "\(cells.count) cells discovered."
                statusIsError = false
            }
        }
    }

    private func finishOnboarding() async {
        mooringBusy = true
        statusMessage = "Creating receipts..."
        statusIsError = false
        let defaults = UserDefaults.standard
        let result = await coordinator.completeOnboardingIfPersistable(
            sshKeyPath: defaults.string(forKey: "fusion_ssh_key_path") ?? "",
            sshUser: defaults.string(forKey: "fusion_ssh_user") ?? "root",
            natsURL: natsURL
        )
        await MainActor.run {
            statusMessage = result.1
            statusIsError = !result.0
            mooringBusy = false
            if result.0 {
                coordinator.showOnboarding = false
            }
        }
    }

}
