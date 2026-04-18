import SwiftUI

struct MeshCellListView: View {
    let cells: [CellState]
    @Binding var selectedCellID: String?
    let onSelect: (String) -> Void
    let onHeal: (String) -> Void
    let onSwap: (CellState) -> Void

    var body: some View {
        ForEach(cells) { cell in
            let isSelected = selectedCellID == cell.id
            Button {
                selectedCellID = cell.id
                onSelect(cell.id)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(dotColor(cell))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortCellLabel(cell.name))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(.primary)
                        Text("\(plantBadge(cell.inputPlantType))/\(plantBadge(cell.outputPlantType)) • \(cell.role)")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(Int(cell.healthPercent))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 2)
                .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Heal") { onHeal(cell.id) }
                Button("Swap Input/Output") { onSwap(cell) }
                Button("View Detail") { onSelect(cell.id) }
                Button("View History") { onSelect(cell.id) }
            }
        }
    }

    private func dotColor(_ cell: CellState) -> Color {
        if cell.active && cell.health >= 0.9 {
            return .green
        }
        if cell.active && cell.health >= 0.5 {
            return .orange
        }
        if cell.active {
            return .yellow
        }
        return .red
    }

    private func plantBadge(_ type: PlantType) -> String {
        String(type.rawValue.prefix(1).uppercased())
    }

    private func shortCellLabel(_ fullID: String) -> String {
        let pieces = fullID.components(separatedBy: "-")
        if let last = pieces.last, last.count <= 8 {
            return last
        }
        return String(fullID.suffix(12))
    }
}
