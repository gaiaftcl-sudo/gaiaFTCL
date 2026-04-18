import SwiftUI

struct FusionToolbar: View {
    @Binding var shellMode: FusionShellMode
    let onModeChange: (FusionShellMode) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { shellMode },
            set: { (newValue: FusionShellMode) in
                shellMode = newValue
                onModeChange(newValue)
            }
        )) {
            ForEach(FusionShellMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .frame(maxWidth: 380)
    }
}
