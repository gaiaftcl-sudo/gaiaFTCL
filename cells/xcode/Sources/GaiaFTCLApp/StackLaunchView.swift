import SwiftUI

struct StackLaunchView: View {
    var launcher: SovereignStackLauncher

    private static let bg    = Color(red: 0.03, green: 0.04, blue: 0.12)
    private static let cyan  = Color(red: 0.00, green: 0.83, blue: 0.98)

    var body: some View {
        ZStack {
            Self.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                if case .failed(let reason) = launcher.phase {
                    Text("TERMINAL STATE: BLOCKED")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(.red)
                    Text(reason)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Self.cyan)
                    if case .launching(let msg) = launcher.phase {
                        Text(msg)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Self.cyan.opacity(0.85))
                    }
                    Text("GaiaFTCL — Sovereign M\u{2078}")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
        }
    }
}
