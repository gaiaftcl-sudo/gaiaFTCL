import AppKit
import SwiftUI

struct AppMenu: Commands {
    let onProbeAllCells: () -> Void
    let onHealUnhealthy: () -> Void
    let onRunPlaywrightUiGate: () -> Void
    let onShowTopology: () -> Void
    let onShowProjection: () -> Void
    let onShowMetrics: () -> Void
    let onShowGrid: () -> Void
    let onSwapSelected: () -> Void
    let onCellDetail: () -> Void
    let onShowHistory: () -> Void
    let onToggleInspector: () -> Void
    let onToggleSidebar: () -> Void
    let onToggleTraceLayer: () -> Void
    let onToggleNativeAgencyChrome: () -> Void
    let onOpenConfig: () -> Void
    let onOpenFusionRunnerConfig: () -> Void
    let onMeshSetupWizard: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void

    var body: some Commands {
        CommandMenu("File") {
            Button("Quit") {
                onQuit()
            }
            .keyboardShortcut("q")
        }

        CommandMenu("Mesh") {
            Button("Mesh setup wizard…") {
                onMeshSetupWizard()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Probe All Cells") {
                onProbeAllCells()
            }
            .keyboardShortcut("p", modifiers: [.command])

            Button("Heal Unhealthy") {
                onHealUnhealthy()
            }
            .keyboardShortcut("h", modifiers: [.command])

            Button("Run Playwright UI Gate (S4 torsion)") {
                onRunPlaywrightUiGate()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift, .option])
        }

        CommandMenu("Cell") {
            Button("Trace Topology View") {
                onShowTopology()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Trace Projection View") {
                onShowProjection()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Trace Metrics View") {
                onShowMetrics()
            }
            .keyboardShortcut("m", modifiers: [.command])

            Button("Trace Grid View") {
                onShowGrid()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("Trace Swap Selected") {
                onSwapSelected()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Cell Detail") {
                onCellDetail()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Swap History") {
                onShowHistory()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Toggle Cell Agency Status Bar") {
                onToggleNativeAgencyChrome()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Button("Toggle Trace Layer") {
                onToggleTraceLayer()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Button("Toggle Inspector") {
                onToggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Toggle Sidebar") {
                onToggleSidebar()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
        }

        CommandMenu("Config") {
            Button("Open fusion_cell config (runner)…") {
                onOpenFusionRunnerConfig()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Preferences…") {
                onOpenConfig()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Help") {
            Button("About GaiaFusion") {
                onAbout()
            }
        }
    }
}
