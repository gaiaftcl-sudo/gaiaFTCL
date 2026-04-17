import SwiftUI

@main
struct FusionSidecarHostApp: App {
    init() {
        FusionMacCLI.handleInvocationInAppInit()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Fusion") {
                Button("Start VM") {
                    NotificationCenter.default.post(name: .fusionStartVM, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Stop VM and Bridge") {
                    NotificationCenter.default.post(name: .fusionStopAll, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command])

                Divider()

                Button("Start Bridge 8803") {
                    NotificationCenter.default.post(name: .fusionStartBridge, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Stop Bridge") {
                    NotificationCenter.default.post(name: .fusionStopBridge, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Divider()

                Button("Reload Control Surface") {
                    NotificationCenter.default.post(name: .fusionControlSurfaceReload, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                // DISCORD_DISABLED_FOR_SWIFT_INVARIANT
            }

            CommandMenu("Onboarding") {
                Button("Run Playwright New User Walkthrough") {
                    NotificationCenter.default.post(name: .fusionRunPlaywrightOnboarding, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}
