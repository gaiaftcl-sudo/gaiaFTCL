import Foundation
import GaiaFTCLCore

public enum VQbitDomain: String, Sendable, Codable, Hashable, CaseIterable {
    case fusion      = "FUSION"
    case health      = "HEALTH"
    case lithography = "LITHOGRAPHY"
    case quantum     = "QUANTUM"
}

public struct VQbit: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID { primID }

    public var domain:         VQbitDomain
    public var primID:         UUID
    public var s1_structural:  Double
    public var s2_temporal:    Double
    public var s3_spatial:     Double
    public var s4_observable:  Double
    public var c1_trust:       Double
    public var c2_identity:    Double
    public var c3_closure:     Double
    public var c4_consequence: Double
    public var terminalState:  TerminalState
    public var timestampUTC:   String

    public var asManifoldState: ManifoldState {
        ManifoldState(
            s1_structural:  s1_structural,  s2_temporal:    s2_temporal,
            s3_spatial:     s3_spatial,     s4_observable:  s4_observable,
            c1_trust:       c1_trust,       c2_identity:    c2_identity,
            c3_closure:     c3_closure,     c4_consequence: c4_consequence,
            timestampUTC: timestampUTC,
            terminalHint: terminalState
        )
    }

    public init(
        domain:         VQbitDomain, primID:         UUID = UUID(),
        s1_structural:  Double,      s2_temporal:    Double,
        s3_spatial:     Double,      s4_observable:  Double,
        c1_trust:       Double,      c2_identity:    Double,
        c3_closure:     Double,      c4_consequence: Double,
        terminalState:  TerminalState,
        timestampUTC:   String
    ) {
        self.domain         = domain
        self.primID         = primID
        self.s1_structural  = s1_structural
        self.s2_temporal    = s2_temporal
        self.s3_spatial     = s3_spatial
        self.s4_observable  = s4_observable
        self.c1_trust       = c1_trust
        self.c2_identity    = c2_identity
        self.c3_closure     = c3_closure
        self.c4_consequence = c4_consequence
        self.terminalState  = terminalState
        self.timestampUTC   = timestampUTC
    }
}
