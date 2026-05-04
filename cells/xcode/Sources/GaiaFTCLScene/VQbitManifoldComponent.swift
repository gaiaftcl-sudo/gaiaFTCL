import RealityKit
import Foundation

public struct VQbitManifoldComponent: Component {
    public var manifoldState: ManifoldState
    public var primID:        UUID

    public init(_ state: ManifoldState, primID: UUID = UUID()) {
        self.manifoldState = state
        self.primID        = primID
    }
}
