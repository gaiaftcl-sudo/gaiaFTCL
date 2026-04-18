import SwiftUI

struct ConfigFileBrowser: View {
    let configManager: ConfigFileManager
    let relativeRoot: String
    @Binding var selectedFile: URL?
    let onSelect: () -> Void

    @State private var nodes: [FileTreeNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if nodes.isEmpty {
                Text("No files found")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            } else {
                OutlineGroup(nodes, children: \.children) { node in
                    if node.isDirectory {
                        Label {
                            Text(node.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "folder.fill")
                        }
                    } else {
                        Button {
                            selectedFile = node.url
                            onSelect()
                        } label: {
                            HStack {
                                Text(node.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text(configManager.modificationLabel(for: node.url))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .onAppear {
            nodes = configManager.fileTree(for: relativeRoot)
        }
    }
}
