import SwiftUI
import RealityKit
import RealityKitContent
import SwiftData
import AppKit
import GaiaFTCLScene
import GaiaFTCLCore

// S4 projection errors — every failure is terminal, no fallback geometry emitted.
enum S4ProjectionError: Error, Sendable {
    case sceneLoadFailed(String, String)    // (sceneName, reason)
    case topologyAnchorNotFound(String)     // scopeName missing from loaded scene
}

extension S4ProjectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sceneLoadFailed(let name, let reason):
            return "Scene '\(name)' load failed: \(reason)"
        case .topologyAnchorNotFound(let scope):
            return "Topology anchor '\(scope)' absent from scene"
        }
    }
}

struct FranklinSceneView: View {
    @Environment(FranklinSceneDirector.self) private var sceneDirector
    @Environment(VQbitStore.self) private var store
    @Environment(ManifoldOverlayStore.self) private var manifoldOverlay
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [CachedSceneEntry] = []
    @State private var rootEntity = Entity()
    @State private var catalogAnchorEntity: Entity? = nil
    @State private var projectionError: S4ProjectionError? = nil
    @State private var manifoldEntity: Entity?
    @State private var coneEntity: Entity?
    @State private var worldDomainsRoot: Entity?
    @State private var fusionPortalEntity: ModelEntity?
    @State private var healthPortalEntity: ModelEntity?
    @State private var didAuditPrimSovereignty = false

    private static let panelBG     = Color(red: 0.03, green: 0.04, blue: 0.12)
    private static let refusedTint = Color(red: 0.537, green: 0.812, blue: 0.941) // #89CFF0
    private static var didRegisterC4Projection = false

    private static func registerC4ProjectionOnce() {
        guard !didRegisterC4Projection else { return }
        VQbitManifoldComponent.registerComponent()
        C4ProjectionSystem.registerSystem()
        didRegisterC4Projection = true
    }

    private var activeCue: String {
        entries.first(where: { $0.sceneID == sceneDirector.activeSceneID })?.franklinCue
            ?? sceneDirector.active.franklinCue
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RealityView { content in
                content.add(rootEntity)
                await materializeS4Projection(sceneDirector.activeSceneID)
            } update: { content in
                _ = content
                updateProjectionVisuals()
            }
            .onChange(of: sceneDirector.activeSceneID) { _, newID in
                Task { @MainActor in await materializeS4Projection(newID) }
            }
            .onAppear { fetchAndHydrate() }

            if let err = projectionError {
                // Terminal REFUSED state — #89CFF0, no procedural substitute.
                VStack(spacing: 4) {
                    Text("REFUSED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.refusedTint)
                    Text(err.errorDescription ?? "S4 projection error")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Self.refusedTint.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.panelBG.opacity(0.85))
            } else {
                // C4 telemetry — franklinCue from SwiftData, moored conceptually to CatalogAnchor.
                VStack(spacing: 4) {
                    Text(activeCue)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.50))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Text(c4OverlaySummary)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(terminalColor.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .background(Self.panelBG)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var terminalColor: Color {
        switch manifoldOverlay.current.terminalState {
        case .blocked: return .purple
        case .refused: return .red
        case .cure: return .orange
        case .calorie: return .cyan
        }
    }

    private var c4OverlaySummary: String {
        let s = manifoldOverlay.current
        return String(
            format: "C4 c1=%.2f c2=%.2f c3=%.2f c4=%.2f  %@",
            s.c1_trust, s.c2_identity, s.c3_closure, s.c4_consequence, s.terminalState.rawValue
        )
    }

    // ── S4 fail-closed pipeline ───────────────────────────────────────────────

    @MainActor
    private func materializeS4Projection(_ sceneID: String) async {
        rootEntity.children.forEach { $0.removeFromParent() }
        catalogAnchorEntity = nil
        do {
            let sub = try await loadStrictS4Projection(sceneID: sceneID)
            projectionError = nil
            rootEntity.addChild(sub)
            catalogAnchorEntity = sub.findEntity(named: "CatalogAnchor")
            ensureOverlayEntities(mount: catalogAnchorEntity ?? sub, openWindow: openWindow)
        } catch let err as S4ProjectionError {
            print("TERMINAL STATE: REFUSED. S4 Projection failed: \(err)")
            projectionError = err
        } catch {
            print("TERMINAL STATE: REFUSED. S4 Projection failed: \(error)")
            projectionError = .sceneLoadFailed(sceneID, error.localizedDescription)
        }
    }

    @MainActor
    private func ensureOverlayEntities(mount: Entity, openWindow: OpenWindowAction) {
        if manifoldEntity == nil {
            let m = ModelEntity(mesh: .generateSphere(radius: 0.05),
                                materials: [SimpleMaterial(color: NSColor.systemCyan.withAlphaComponent(0.45), isMetallic: false)])
            m.name = "ManifoldField"
            m.position = [0, 0.15, 0]
            m.components.set(VQbitManifoldComponent(manifoldOverlay.current))
            manifoldEntity = m
            mount.addChild(m)
        }
        if coneEntity == nil {
            let c = ModelEntity(mesh: .generateCone(height: 0.20, radius: 0.10),
                                materials: [SimpleMaterial(color: NSColor.systemCyan.withAlphaComponent(0.25), isMetallic: false)])
            c.name = "ConeOfSafety"
            c.position = [0, 0.05, 0]
            coneEntity = c
            mount.addChild(c)
        }
        if worldDomainsRoot == nil {
            let world = Entity()
            world.name = "World"
            let domains = Entity()
            domains.name = "Domains"
            let fusionDom = Entity()
            fusionDom.name = "Fusion"
            let healthDom = Entity()
            healthDom.name = "Health"
            let fusionPrim = GaiaFTCLPrimIdentity.uuid(
                gameID: LanguageGameContractSeed.fusionGameID,
                domain: "fusion"
            )
            let healthPrim = GaiaFTCLPrimIdentity.uuid(
                gameID: LanguageGameContractSeed.healthGameID,
                domain: "health"
            )
            let envelopeMat = SimpleMaterial(color: NSColor.systemCyan.withAlphaComponent(0.35), isMetallic: false)
            let fusionEnvelope = ModelEntity(
                mesh: .generateBox(width: 0.06, height: 0.06, depth: 0.06),
                materials: [envelopeMat]
            )
            fusionEnvelope.name = LanguageGameContractSeed.fusionGameID
            fusionEnvelope.position = [0, 0, 0]
            fusionEnvelope.components.set(VQbitManifoldComponent(restingManifoldHint(.calorie), primID: fusionPrim))
            let healthEnvelope = ModelEntity(
                mesh: .generateBox(width: 0.06, height: 0.06, depth: 0.06),
                materials: [SimpleMaterial(color: NSColor.systemTeal.withAlphaComponent(0.35), isMetallic: false)]
            )
            healthEnvelope.name = LanguageGameContractSeed.healthGameID
            healthEnvelope.position = [0, 0, 0]
            healthEnvelope.components.set(VQbitManifoldComponent(restingManifoldHint(.calorie), primID: healthPrim))
            fusionDom.addChild(fusionEnvelope)
            healthDom.addChild(healthEnvelope)
            domains.addChild(fusionDom)
            domains.addChild(healthDom)
            world.addChild(domains)
            worldDomainsRoot = world
            mount.addChild(world)
        }

        if fusionPortalEntity == nil {
            let fusionPrim = GaiaFTCLPrimIdentity.uuid(
                gameID: LanguageGameContractSeed.fusionGameID,
                domain: "fusion"
            )
            let fp = ModelEntity(
                mesh: .generatePlane(width: 0.09, depth: 0.09),
                materials: [SimpleMaterial(color: NSColor.systemBlue.withAlphaComponent(0.45), isMetallic: false)]
            )
            fp.name = "PortalFusionDomain"
            fp.position = [0.22, 0.08, 0.02]
            fp.components.set(VQbitManifoldComponent(restingManifoldHint(.calorie), primID: fusionPrim))
            Self.configureDomainPortal(fp, domain: "fusion", openWindow: openWindow)
            fusionPortalEntity = fp
            mount.addChild(fp)
        }
        if healthPortalEntity == nil {
            let healthPrim = GaiaFTCLPrimIdentity.uuid(
                gameID: LanguageGameContractSeed.healthGameID,
                domain: "health"
            )
            let hp = ModelEntity(
                mesh: .generatePlane(width: 0.09, depth: 0.09),
                materials: [SimpleMaterial(color: NSColor.systemGreen.withAlphaComponent(0.45), isMetallic: false)]
            )
            hp.name = "PortalHealthDomain"
            hp.position = [-0.22, 0.08, 0.02]
            hp.components.set(VQbitManifoldComponent(restingManifoldHint(.calorie), primID: healthPrim))
            Self.configureDomainPortal(hp, domain: "health", openWindow: openWindow)
            healthPortalEntity = hp
            mount.addChild(hp)
        }
    }

    /// Stable hover correlation groups for C⁴ / **`hover_intensity`** (one id per sovereign domain).
    private static let fusionPortalHoverGroupID = HoverEffectComponent.GroupID()
    private static let healthPortalHoverGroupID = HoverEffectComponent.GroupID()

    /// Spatial grab + hover highlight + tap → **`openWindow(id: "domain-{domain}")`**.
    /// RealityFoundation exposes **`ManipulationComponent.configureEntity`** only on visionOS (marked **`unavailable`** on macOS in the public swiftinterface); portals use **`InputTarget`** + **`Collision`** + **`HoverEffect`** + **`GestureComponent`** on GaiaFTCL macOS.
    private static func configureDomainPortal(_ portal: ModelEntity, domain: String, openWindow: OpenWindowAction) {
        portal.components.set(InputTargetComponent())
        portal.components.set(CollisionComponent(shapes: [.generateBox(width: 0.09, height: 0.02, depth: 0.09)], mode: .trigger))
        let groupID = domain == "fusion" ? fusionPortalHoverGroupID : healthPortalHoverGroupID
        let hoverFX = HoverEffectComponent.HoverEffect.spotlight(.default, groupID: groupID)
        portal.components.set(HoverEffectComponent(hoverFX))
        portal.components.set(
            GestureComponent(
                TapGesture().onEnded {
                    openWindow(id: "domain-\(domain)")
                }
            )
        )
    }

    private func restingManifoldHint(_ terminal: TerminalState) -> ManifoldState {
        ManifoldState(
            s1_structural: 0,
            s2_temporal: 0,
            s3_spatial: 0,
            s4_observable: 0,
            c1_trust: 0.55,
            c2_identity: 0.55,
            c3_closure: 0.55,
            c4_consequence: 0.55,
            timestampUTC: ISO8601DateFormatter().string(from: Date()),
            terminalHint: terminal
        )
    }

    @MainActor
    private func updateProjectionVisuals() {
        Self.registerC4ProjectionOnce()
        if Date() >= C4ManifoldRuntimeBridge.natsAuthorityUntil {
            C4ManifoldRuntimeBridge.latestManifold = manifoldOverlay.current
        }
        guard let manifoldEntity, let coneEntity else { return }
        let state = manifoldOverlay.current
        if var comp = manifoldEntity.components[ModelComponent.self],
           comp.materials.first as? SimpleMaterial != nil {
            let next = SimpleMaterial(color: terminalNSColor(alpha: 0.5), isMetallic: false)
            comp.materials = [next]
            manifoldEntity.components[ModelComponent.self] = comp
        }
        manifoldEntity.scale = .init(
            x: Float(0.5 + state.c4_consequence),
            y: Float(0.5 + state.c1_trust),
            z: Float(0.5 + state.c3_closure)
        )
        coneEntity.orientation = simd_quatf(angle: Float(state.s2_temporal * 2.0 * .pi), axis: [0, 1, 0])
        coneEntity.scale = .one * Float(0.5 + state.c3_closure)
        if !didAuditPrimSovereignty, worldDomainsRoot != nil {
            didAuditPrimSovereignty = true
            Task { await FranklinPrimSovereigntyAudit.auditPrimSovereignty(rootEntity: rootEntity) }
        }
    }

    private func terminalNSColor(alpha: CGFloat) -> NSColor {
        switch manifoldOverlay.current.terminalState {
        case .blocked: return NSColor.systemPurple.withAlphaComponent(alpha)
        case .refused: return NSColor.systemRed.withAlphaComponent(alpha)
        case .cure: return NSColor.systemOrange.withAlphaComponent(alpha)
        case .calorie: return NSColor.systemCyan.withAlphaComponent(alpha)
        }
    }

    @MainActor
    private func loadStrictS4Projection(sceneID: String) async throws -> Entity {
        guard let entry = FranklinSceneDirector.catalog[sceneID] else {
            throw S4ProjectionError.topologyAnchorNotFound(sceneID)
        }
        let fileName = String(entry.file.dropLast(5)) // strip ".usda"
        let rootScene: Entity
        do {
            rootScene = try await Entity(named: fileName, in: realityKitContentBundle)
        } catch {
            throw S4ProjectionError.sceneLoadFailed(fileName, error.localizedDescription)
        }
        guard let sub = rootScene.findEntity(named: entry.scope) else {
            throw S4ProjectionError.topologyAnchorNotFound(entry.scope)
        }
        return sub
    }

    // ── C4 → SwiftData: ingest + hydrate ──────────────────────────────────────

    private func fetchAndHydrate() {
        let descriptor = FetchDescriptor<CachedSceneEntry>()
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        let existingIDs = Set(stored.map(\.sceneID))
        let missing = FranklinSceneDirector.catalog.keys.filter { !existingIDs.contains($0) }
        for sceneID in missing {
            guard let entry = FranklinSceneDirector.catalog[sceneID] else { continue }
            let cached = CachedSceneEntry(
                sceneID:     entry.sceneID,
                file:        entry.file,
                scope:       entry.scope,
                franklinCue: entry.franklinCue,
                domain:      CachedSceneEntry.domain(for: entry.sceneID)
            )
            cached.approvedByVQbit   = true
            cached.approvalTimestamp = Date()
            modelContext.insert(cached)
        }
        if !missing.isEmpty { try? modelContext.save() }
        entries = (try? modelContext.fetch(descriptor)) ?? []
    }
}
