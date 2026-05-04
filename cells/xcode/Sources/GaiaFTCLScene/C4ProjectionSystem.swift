import RealityKit
import Foundation

// RealityKit System — runs every render tick.
// Reads C4 projections from C4ManifoldRuntimeBridge and writes them onto
// every entity that carries a VQbitManifoldComponent.
public struct C4ProjectionSystem: System {
    private static let query = EntityQuery(where: .has(VQbitManifoldComponent.self))

    public init(scene: Scene) {}

    public func update(context: SceneUpdateContext) {
        let manifolds = C4ManifoldRuntimeBridge.primManifolds
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var comp = entity.components[VQbitManifoldComponent.self],
                  let updated = manifolds[comp.primID]
            else { continue }
            comp.manifoldState = updated
            entity.components.set(comp)
        }
    }
}
