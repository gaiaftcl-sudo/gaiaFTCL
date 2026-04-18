import SwiftUI

struct CellDetailTab: View {
    let cell: CellState
    let onHeal: () -> Void
    let onSwap: () -> Void
    @Binding var selectedSwapInput: String
    @Binding var selectedSwapOutput: String
    let onOpenConfig: () -> Void
    let onOpenSSHTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cell: \(cell.name)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack(spacing: 14) {
                labelPair("IP", cell.ipv4)
                labelPair("Health", "\(Int(cell.healthPercent))%")
                labelPair("Uptime", "0h")
                labelPair("Status", cell.status)
            }
            .font(.system(size: 11, design: .monospaced))

            HStack(spacing: 14) {
                labelPair("Input", cell.inputPlantType.rawValue)
                labelPair("Output", cell.outputPlantType.rawValue)
                labelPair("Active", cell.active ? "true" : "false")
            }
            .font(.system(size: 11, design: .monospaced))

            Divider()

            Text("Last swap: none")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Last heal: n/a")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("NATS subjects: gaiaftcl.cell.\(cell.id)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack {
                PlantKindPicker(label: "Input", selection: $selectedSwapInput)
                PlantKindPicker(label: "Output", selection: $selectedSwapOutput)
            }

            HStack {
                Button("Heal", action: onHeal)
                    .buttonStyle(.bordered)
                Button("Swap", action: onSwap)
                    .buttonStyle(.borderedProminent)
                Button("SSH Terminal", action: onOpenSSHTerminal)
                    .buttonStyle(.bordered)
                Button("View Config", action: onOpenConfig)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func labelPair(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}
