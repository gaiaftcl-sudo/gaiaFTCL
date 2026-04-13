import SwiftUI

struct PlantKindPicker: View {
    let label: String
    @Binding var selection: String

    private var kinds: [String] {
        PlantKindsCatalog.canonicalKinds.sorted()
    }

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(kinds, id: \.self) { kind in
                Text(kind.capitalized).tag(kind)
            }
        }
        .pickerStyle(.menu)
    }
}

