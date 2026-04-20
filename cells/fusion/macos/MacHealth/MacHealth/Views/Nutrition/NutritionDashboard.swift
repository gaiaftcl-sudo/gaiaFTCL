// NutritionDashboard.swift — twelve mothers at a glance [I]
import SwiftUI

struct NutritionDashboard: View {
    let mothers: [String] = [
        "MACRO", "MICRO", "METABOLIC", "INFLAMMATORY", "MICROBIOME", "CARDIO",
        "HEPATO-RENAL", "HORMONAL", "NEURO", "ENVIRONMENTAL", "DIGESTIVE", "CHRONO"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition Dashboard")
                    .font(.title2)
                C4FilterBadge(summary: "[I] user filters")
                ForEach(mothers, id: \.self) { m in
                    HStack {
                        Text("OWL-NUTRITION-\(m)-001")
                        Spacer()
                        Text("coherence [I]")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
        }
    }
}
