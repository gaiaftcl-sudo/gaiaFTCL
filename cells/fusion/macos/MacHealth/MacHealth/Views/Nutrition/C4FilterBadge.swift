// C4FilterBadge.swift — visible declared constraint badge (WCAG: label + icon) [I]
import SwiftUI

struct C4FilterBadge: View {
    let summary: String

    var body: some View {
        Label(summary, systemImage: "leaf.fill")
            .accessibilityLabel(Text("Declared nutrition filters: \(summary)"))
    }
}
