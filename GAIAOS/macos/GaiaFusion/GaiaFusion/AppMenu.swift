import AppKit
import SwiftUI

struct AppMenu: Commands {
    // Authorization state
    let operationalState: PlantOperationalState
    let userLevel: OperatorRole
    
    // File menu actions
    let onNewSession: () -> Void
    let onOpenPlantConfig: () -> Void
    let onSaveSnapshot: () -> Void
    let onExportAuditLog: () -> Void
    let onQuit: () -> Void
    
    // Cell menu actions
    let onSwapPlant: () -> Void
    let onArmIgnition: () -> Void
    let onEmergencyStop: () -> Void
    let onResetTrip: () -> Void
    let onAcknowledgeAlarm: () -> Void
    
    // Mesh menu actions
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
    
    // Config menu actions
    let onOpenConfig: () -> Void
    let onOpenFusionRunnerConfig: () -> Void
    let onMeshSetupWizard: () -> Void
    let onTrainingMode: () -> Void
    let onMaintenanceMode: () -> Void
    let onAuthSettings: () -> Void
    
    // Help menu actions
    let onAbout: () -> Void
    let onViewAuditLog: () -> Void
    
    // Composite layout shortcuts
    let onLayoutDashboardFocus: () -> Void
    let onLayoutGeometryFocus: () -> Void
    let onToggleConstitutionalHud: () -> Void
    let onCycleMetalOpacity: () -> Void

    var body: some Commands {
        // File Menu — Complete per OPERATOR_AUTHORIZATION_MATRIX.md
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                onNewSession()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!([.idle, .training].contains(operationalState)))
            
            Button("Open Plant Configuration...") {
                onOpenPlantConfig()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!([.idle, .maintenance].contains(operationalState)) || !userLevel.isAtLeast(.l2))
            
            Button("Save Snapshot") {
                onSaveSnapshot()
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Export Audit Log...") {
                onExportAuditLog()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!userLevel.isAtLeast(.l2))
            
            Divider()
            
            Button("Quit GaiaFusion") {
                onQuit()
            }
            .keyboardShortcut("q", modifiers: .command)
            .disabled(!([.idle, .training].contains(operationalState)))
        }
        
        // Remove Edit, View, Window menus (regulatory prohibition)
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .windowList) { }
        CommandGroup(replacing: .appSettings) { }
        
        // Cell Menu — Plant control actions
        CommandMenu("Cell") {
            Button("Swap Plant...") {
                onSwapPlant()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(!([.idle, .maintenance].contains(operationalState)) || !userLevel.isAtLeast(.l2))
            
            Button("Arm Ignition") {
                onArmIgnition()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(operationalState != .moored || !userLevel.isAtLeast(.l2))
            
            Button("Emergency Stop") {
                onEmergencyStop()
            }
            .keyboardShortcut("x", modifiers: [.command])
            .disabled(operationalState != .running)
            
            Button("Reset Trip...") {
                onResetTrip()
            }
            .disabled(operationalState != .tripped || !userLevel.isAtLeast(.l2))
            
            Button("Acknowledge Alarm") {
                onAcknowledgeAlarm()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(operationalState != .constitutionalAlarm || !userLevel.isAtLeast(.l2))
            
            Divider()
            
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

        // Mesh Menu — Mesh infrastructure operations
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

        // Config Menu — System configuration and modes
        CommandMenu("Config") {
            Button("Training Mode") {
                onTrainingMode()
            }
            .disabled(operationalState != .idle || !userLevel.isAtLeast(.l2))
            
            Button("Maintenance Mode") {
                onMaintenanceMode()
            }
            .disabled(operationalState != .idle || !userLevel.isAtLeast(.l3))
            
            Button("Authorization Settings...") {
                onAuthSettings()
            }
            .disabled(operationalState != .idle || !userLevel.isAtLeast(.l3))
            
            Divider()
            
            Button("Open fusion_cell config (runner)…") {
                onOpenFusionRunnerConfig()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Preferences…") {
                onOpenConfig()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Help Menu — Documentation and audit access
        CommandGroup(replacing: .help) {
            Button("About GaiaFusion") {
                onAbout()
            }
            
            Button("View Audit Log") {
                onViewAuditLog()
            }
            .disabled(!userLevel.isAtLeast(.l2))
        }
    }
}
