import Foundation
import Observation

@MainActor
@Observable
final class AppPhaseModel {
    enum AppPhase: Equatable {
        case preparing
        case avatarWake
        case operatorSurface
        case failed([String])
    }

    private(set) var phase: AppPhase = .preparing
    private(set) var launchGate = FranklinLaunchGate.evaluate()
    private(set) var startupWarnings: [String] = []
    private let configuration = FranklinAppConfiguration.load()
    private var bootstrapped = false

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        phase = .preparing
        launchGate = FranklinLaunchGate.evaluate()
        guard launchGate.ready else {
            startupWarnings = launchGate.refusals
            phase = configuration.enforceHardLaunchGate ? .failed(launchGate.refusals) : .avatarWake
            if !configuration.enforceHardLaunchGate {
                try? await Task.sleep(for: .milliseconds(900))
                phase = .operatorSurface
            }
            return
        }

        let binding = FranklinAvatarAssetBinding.load()
        var failures: [String] = []
        if !binding.passyAssetSetReady {
            failures.append("GW_REFUSE_AVATAR_PASSY_ASSET_SET_MISSING")
            failures.append(contentsOf: binding.missingAssets.prefix(3))
        }
        if !binding.meshLoaded {
            failures.append("GW_REFUSE_AVATAR_MESH_ASSET_MISSING")
        }
        if !binding.meshDetailSufficient {
            failures.append("GW_REFUSE_AVATAR_MESH_DETAIL_INSUFFICIENT")
        }
        if !failures.isEmpty {
            startupWarnings = failures
            phase = configuration.enforceHardLaunchGate ? .failed(failures) : .avatarWake
            if !configuration.enforceHardLaunchGate {
                try? await Task.sleep(for: .milliseconds(900))
                phase = .operatorSurface
            }
            return
        }

        phase = .avatarWake
        try? await Task.sleep(for: .milliseconds(900))
        phase = .operatorSurface
    }
}
