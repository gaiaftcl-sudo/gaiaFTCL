import Foundation
import GaiaFTCLCore

public struct MeshVQbitPayload: Codable, Sendable {
    public let cellID:          String
    public let domain:          String
    public let primID:          String
    public let s1_structural:   Double
    public let s2_temporal:     Double
    public let s3_spatial:      Double
    public let s4_observable:   Double
    public let c1_trust:        Double
    public let c2_identity:     Double
    public let c3_closure:      Double
    public let c4_consequence:  Double
    public let terminalState:   String
    public let timestampUTC:    String

    public init(from vqbit: VQbit, cellID: String) {
        self.cellID         = cellID
        self.domain         = vqbit.domain.rawValue
        self.primID         = vqbit.primID.uuidString
        self.s1_structural  = vqbit.s1_structural
        self.s2_temporal    = vqbit.s2_temporal
        self.s3_spatial     = vqbit.s3_spatial
        self.s4_observable  = vqbit.s4_observable
        self.c1_trust       = vqbit.c1_trust
        self.c2_identity    = vqbit.c2_identity
        self.c3_closure     = vqbit.c3_closure
        self.c4_consequence = vqbit.c4_consequence
        self.terminalState  = vqbit.terminalState.rawValue
        self.timestampUTC   = vqbit.timestampUTC
    }

    public func toVQbit() -> VQbit? {
        guard let domain   = VQbitDomain(rawValue: domain),
              let primID   = UUID(uuidString: primID),
              let terminal = TerminalState(rawValue: terminalState)
        else { return nil }
        return VQbit(
            domain:         domain,        primID:         primID,
            s1_structural:  s1_structural, s2_temporal:    s2_temporal,
            s3_spatial:     s3_spatial,    s4_observable:  s4_observable,
            c1_trust:       c1_trust,      c2_identity:    c2_identity,
            c3_closure:     c3_closure,    c4_consequence: c4_consequence,
            terminalState:  terminal,
            timestampUTC:   timestampUTC
        )
    }
}
