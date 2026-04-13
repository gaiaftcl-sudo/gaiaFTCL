import Foundation
import SwiftUI

struct ReceiptViewerTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var receiptText: String = ""

    var body: some View {
        VStack(spacing: 8) {
            if let fileURL = coordinator.selectedReceiptFileURL {
                Text(fileURL.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(highlightedLines.indices, id: \.self) { idx in
                            Text(highlightedLines[idx].text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(highlightedLines[idx].color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .padding(.vertical, 1)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: .infinity)
            } else {
                Text("Select a receipt file in the Results section.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadReceipt(from: coordinator.selectedReceiptFileURL)
        }
        .onChange(of: coordinator.selectedReceiptFileURL) { _, newValue in
            loadReceipt(from: newValue)
        }
    }

    private func loadReceipt(from fileURL: URL?) {
        guard let fileURL else {
            receiptText = ""
            return
        }
        receiptText = coordinator.configManager.readText(from: fileURL) ?? ""
    }

    private var formattedReceipt: String {
        guard !receiptText.isEmpty else { return "No receipt payload." }
        if let data = receiptText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? NSObject,
           let pretty = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys]),
           let out = String(data: pretty, encoding: .utf8) {
            return out
        }
        return receiptText
    }

    private var highlightedLines: [(text: String, color: Color)] {
        formattedReceipt
            .components(separatedBy: .newlines)
            .map { line in
                if line.contains("\"terminal\"") {
                    if line.contains("\"CALORIE\"") { return (line, Color.green) }
                    if line.contains("\"REFUSED\"") { return (line, Color.red) }
                    if line.contains("\"PARTIAL\"") { return (line, Color.orange) }
                    return (line, .primary)
                }
                if line.contains("\"status\"") {
                    if line.contains("\"CALORIE\"") { return (line, Color.green) }
                    if line.contains("\"REFUSED\"") { return (line, Color.red) }
                    if line.contains("\"PARTIAL\"") { return (line, Color.orange) }
                }
                return (line, .primary)
            }
    }

}
