import SwiftUI

struct ConfigEditorTab: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var draftText: String = ""
    @State private var loadedURL: URL?
    @State private var isJSONValid = true
    @State private var validationMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            if let fileURL = coordinator.selectedConfigFileURL {
                Text(fileURL.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $draftText)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(4)
                    .background(isJSONValid ? Color.clear : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isJSONValid ? Color.secondary.opacity(0.3) : Color.red, lineWidth: 1)
                    )
                    .onChange(of: draftText) { _, newValue in
                        isJSONValid = coordinator.configManager.isValidJSON(newValue)
                        validationMessage = isJSONValid ? "" : "Invalid JSON"
                    }
                    .frame(maxHeight: .infinity)

                HStack {
                    Text(validationMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(isJSONValid ? .green : .red)
                    Spacer()
                    Button("Save") {
                        guard let target = loadedURL else { return }
                        do {
                            try coordinator.configManager.write(text: draftText, to: target)
                            validationMessage = "Saved ✓"
                        } catch {
                            validationMessage = error.localizedDescription
                        }
                    }
                    .disabled(!isJSONValid)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                }
            } else {
                Text("Select a config JSON file in the sidebar.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            reloadConfig(from: coordinator.selectedConfigFileURL)
        }
        .onChange(of: coordinator.selectedConfigFileURL) { _, newValue in
            reloadConfig(from: newValue)
        }
    }

    private func reloadConfig(from fileURL: URL?) {
        loadedURL = fileURL
        guard let fileURL else {
            draftText = ""
            isJSONValid = true
            validationMessage = ""
            return
        }
        draftText = coordinator.configManager.readText(from: fileURL) ?? ""
        isJSONValid = coordinator.configManager.isValidJSON(draftText)
        if draftText.isEmpty {
            validationMessage = "File is empty"
            isJSONValid = false
        } else {
            validationMessage = isJSONValid ? "Loaded" : "Invalid JSON"
        }
    }
}
