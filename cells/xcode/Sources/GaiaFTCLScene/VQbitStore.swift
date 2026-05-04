import Foundation
import Observation

@Observable
@MainActor
public final class VQbitStore {
    public var vqbits: [VQbitDomain: [VQbit]] = [:]

    public init() {}

    public func ingest(_ vqbit: VQbit) {
        vqbits[vqbit.domain, default: []].append(vqbit)
        C4ManifoldRuntimeBridge.update(primID: vqbit.primID, state: vqbit.asManifoldState)
    }
}
