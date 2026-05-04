import Foundation
import Observation

@Observable
@MainActor
public final class ManifoldOverlayStore {
    public var current: ManifoldState = .resting

    public init() {}

    public func update(_ state: ManifoldState) {
        current = state
    }
}
