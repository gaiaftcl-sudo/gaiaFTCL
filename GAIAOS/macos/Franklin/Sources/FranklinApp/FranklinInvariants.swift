import Foundation

@MainActor
final class FranklinInvariants: ObservableObject {
    private(set) var lastVQbit: Float = 0
    let targetFPS: UInt16 = 29
    let targetInterval: TimeInterval = 1.0 / 29.0
    let minDelta: Float = 0.001

    func allowStateTransition(currentVQbit: Float) -> Bool {
        let delta = abs(currentVQbit - lastVQbit)
        guard delta > minDelta else { return false }
        lastVQbit = currentVQbit
        return true
    }
}
