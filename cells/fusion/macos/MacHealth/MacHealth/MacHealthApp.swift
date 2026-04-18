// MacHealthApp.swift — GaiaHealth Biologit Cell Mac App
// GAMP 5 Category 5 | Zero-PII | M/I/A Epistemic Metal renderer
// Patents: USPTO 19/460,960 | USPTO 19/096,071 — © 2026 Richard Gillespie

import SwiftUI

@main
struct MacHealthApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacHealth") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "MacHealth",
                        .applicationVersion: "0.1.0",
                        .credits: NSAttributedString(
                            string: "GaiaHealth Biologit Cell — GAMP 5 Cat 5\nPatents: USPTO 19/460,960 | 19/096,071",
                            attributes: [:]
                        )
                    ])
                }
            }
        }
    }
}
