import Foundation
import GaiaFTCLCore
import GaiaFTCLScene
import GaiaGateKit
import os
import RealityKit
import VQbitSubstrate

/// **BLOCK 1** — os_log **SOVEREIGN** / **UNMOORED** for each contract manifold prim (tensor row · C⁴ bridge · RealityKit **`VQbitManifoldComponent`**).
@MainActor
enum FranklinPrimSovereigntyAudit {
    private static let log = Logger(subsystem: "com.gaiaftcl", category: "sovereignty")

    static func auditPrimSovereignty(rootEntity: Entity) async {
        guard let pool = try? await SubstrateDatabase.shared.pool() else {
            log.error("auditPrimSovereignty: substrate pool unavailable")
            return
        }
        let repo = FranklinDocumentRepository(db: pool)
        guard let surfaces = try? repo.fetchLanguageGameContractSurfaces() else {
            log.error("auditPrimSovereignty: contract fetch failed")
            return
        }
        let tensorURL = GaiaInstallPaths.manifoldTensorURL
        var seen = Set<UUID>()
        for c in surfaces {
            guard let domain = c.domain?.lowercased() else { continue }
            let pid = GaiaFTCLPrimIdentity.primID(contractGameID: c.gameID, contractDomain: domain)
            guard seen.insert(pid).inserted else { continue }
            let tensorOk = ManifoldTensorStore.hasRow(for: pid, tensorPath: tensorURL)
            let projOk = C4ManifoldRuntimeBridge.primManifolds[pid] != nil
            let entityOk = entityCarriesPrim(rootEntity, primID: pid)
            if tensorOk, projOk, entityOk {
                log.info("SOVEREIGN prim=\(pid.uuidString)")
            } else {
                log.error("UNMOORED prim=\(pid.uuidString) tensor=\(tensorOk) projection=\(projOk) entity=\(entityOk)")
            }
        }
    }

    private static func entityCarriesPrim(_ root: Entity, primID: UUID) -> Bool {
        func walk(_ e: Entity) -> Bool {
            if let c = e.components[VQbitManifoldComponent.self], c.primID == primID { return true }
            for child in e.children where walk(child) { return true }
            return false
        }
        return walk(root)
    }
}
