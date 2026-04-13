import SwiftUI

struct FusionSidebarView: View {
    let meshManager: MeshStateManager
    let configManager: ConfigFileManager

    @Binding var selectedCellID: String?
    @Binding var selectedConfigFileURL: URL?
    @Binding var selectedReceiptFileURL: URL?

    let onRefresh: () -> Void
    let onCellSelect: (String) -> Void
    let onHealCell: (String) -> Void
    let onSwapCell: (CellState) -> Void
    let onConfigSelect: () -> Void
    let onReceiptSelect: () -> Void

    var body: some View {
        List {
            Section(
                header: SidebarSectionHeader(
                    title: "Mesh Status",
                    onAction: onRefresh
                )
            ) {
                MeshCellListView(
                    cells: meshManager.cells,
                    selectedCellID: $selectedCellID,
                    onSelect: { cellID in
                        selectedConfigFileURL = nil
                        selectedReceiptFileURL = nil
                        onCellSelect(cellID)
                    },
                    onHeal: onHealCell,
                    onSwap: onSwapCell
                )
            }

            Section(header: SidebarSectionHeader(title: "Config Files", onAction: nil)) {
                ConfigFileBrowser(
                    configManager: configManager,
                    relativeRoot: "config",
                    selectedFile: $selectedConfigFileURL,
                    onSelect: {
                        onConfigSelect()
                        selectedReceiptFileURL = nil
                    }
                )
            }

            Section(
                header: SidebarSectionHeader(title: "Results", onAction: nil)
            ) {
                ResultsBrowser(
                    configManager: configManager,
                    relativeRoot: "evidence",
                    selectedFile: $selectedReceiptFileURL,
                    onSelect: {
                        onReceiptSelect()
                        selectedConfigFileURL = nil
                    }
                )
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let onAction: (() -> Void)?

    init(title: String, onAction: (() -> Void)? = nil) {
        self.title = title
        self.onAction = onAction
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if let onAction {
                Button(action: onAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh mesh state")
            }
        }
    }
}
