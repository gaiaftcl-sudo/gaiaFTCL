// NutritionIntakeTab.swift — §5.2.6 analog (GaiaHealth-internal spec) [I]
import SwiftUI

struct NutritionIntakeTab: View {
    @ObservedObject var projection: NutritionProjectionService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutrition Intake")
                .font(.headline)
            Text("Food log / lab / CGM import — PHI scrubber before seal [I]")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Simulate projection") {
                projection.projectMotherInvariant(motherId: "OWL-NUTRITION-MACRO-001", evidenceJSON: "{}")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
}
