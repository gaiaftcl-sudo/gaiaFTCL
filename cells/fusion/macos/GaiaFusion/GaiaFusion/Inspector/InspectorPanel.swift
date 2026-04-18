import SwiftUI

enum InspectorPanelTab: String, CaseIterable, Identifiable {
    case cellDetail = "Cell Detail"
    case configEditor = "Config Editor"
    case receiptViewer = "Receipt Viewer"

    var id: String { rawValue }
}

struct InspectorPanel: View {
    @ObservedObject var coordinator: AppCoordinator

    var selectedCell: CellState {
        coordinator.meshManager.cells.first(where: { $0.id == coordinator.selectedCellID }) ?? .fallback
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("INSPECTOR")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Picker("", selection: selectedTab) {
                ForEach(InspectorPanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            Group {
                switch selectedTab.wrappedValue {
                case .cellDetail:
                    CellDetailTab(
                        cell: selectedCell,
                        onHeal: { coordinator.healCell(selectedCell.id) },
                        onSwap: {
                            coordinator.swapCell(
                                cellID: selectedCell.id,
                                inputPlantType: coordinator.selectedSwapInput,
                                outputPlantType: coordinator.selectedSwapOutput,
                            )
                        },
                        selectedSwapInput: $coordinator.selectedSwapInput,
                        selectedSwapOutput: $coordinator.selectedSwapOutput,
                        onOpenConfig: {
                            coordinator.openConfigForCell(selectedCell.id)
                        },
                        onOpenSSHTerminal: {
                            coordinator.openSSHTerminal(for: selectedCell.id)
                        }
                    )
                case .configEditor:
                    ConfigEditorTab(coordinator: coordinator)
                case .receiptViewer:
                    ReceiptViewerTab(coordinator: coordinator)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var selectedTab: Binding<InspectorPanelTab> {
        Binding(
            get: { coordinator.selectedInspectorTab },
            set: { coordinator.selectedInspectorTab = $0 }
        )
    }
}
