// NutritionConfigurationPanel.swift — Settings tab analog [I]
import SwiftUI

struct NutritionConfigurationPanel: View {
    @State private var ethical: String = "vegetarian"
    @State private var religious: String = "halal"

    var body: some View {
        Form {
            Picker("Ethical framework", selection: $ethical) {
                Text("None").tag("none")
                Text("Vegetarian").tag("vegetarian")
                Text("Vegan").tag("vegan")
            }
            Picker("Religious framework", selection: $religious) {
                Text("None").tag("none")
                Text("Halal").tag("halal")
                Text("Kosher").tag("kosher")
            }
            Text("Cadence & alerts [I]")
                .font(.caption)
        }
        .padding()
    }
}
