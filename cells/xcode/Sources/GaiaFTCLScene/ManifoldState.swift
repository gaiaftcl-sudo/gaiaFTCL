import Foundation
import GaiaFTCLCore

public struct ManifoldState: Sendable, Codable, Hashable {
    public var s1_structural:  Double
    public var s2_temporal:    Double
    public var s3_spatial:     Double
    public var s4_observable:  Double
    public var c1_trust:       Double
    public var c2_identity:    Double
    public var c3_closure:     Double
    public var c4_consequence: Double
    public var timestampUTC:   String
    public var terminalHint:   TerminalState

    public var terminalState: TerminalState { terminalHint }

    public static let resting = ManifoldState(
        s1_structural: 0.55,  s2_temporal: 0.55,
        s3_spatial: 0.55,     s4_observable: 0.55,
        c1_trust: 0.55,       c2_identity: 0.55,
        c3_closure: 0.55,     c4_consequence: 0.55,
        timestampUTC: "resting",
        terminalHint: .calorie
    )

    public init(
        s1_structural:  Double, s2_temporal:    Double,
        s3_spatial:     Double, s4_observable:  Double,
        c1_trust:       Double, c2_identity:    Double,
        c3_closure:     Double, c4_consequence: Double,
        timestampUTC: String,
        terminalHint: TerminalState
    ) {
        self.s1_structural  = s1_structural
        self.s2_temporal    = s2_temporal
        self.s3_spatial     = s3_spatial
        self.s4_observable  = s4_observable
        self.c1_trust       = c1_trust
        self.c2_identity    = c2_identity
        self.c3_closure     = c3_closure
        self.c4_consequence = c4_consequence
        self.timestampUTC   = timestampUTC
        self.terminalHint   = terminalHint
    }
}
