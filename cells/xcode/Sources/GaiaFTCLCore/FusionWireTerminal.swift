import Foundation

extension FusionConstitutionalSnapshot {
    /// Maps substrate IQ output to **C4ProjectionWire.terminal** visual bytes (**1…4**, see `TerminalWireBridge`).
    public var c4WireTerminal: UInt8 {
        if violationCode != 0 { return TerminalWireBridge.visualCode(for: .refused) }
        switch terminalState {
        case 0: return TerminalWireBridge.visualCode(for: .calorie)
        case 1: return TerminalWireBridge.visualCode(for: .cure)
        case 2: return TerminalWireBridge.visualCode(for: .refused)
        default: return TerminalWireBridge.visualCode(for: .refused)
        }
    }
}
