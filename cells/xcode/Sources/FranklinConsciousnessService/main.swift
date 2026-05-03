import Foundation
import FranklinConsciousness

let args = CommandLine.arguments

if args.contains("--preflight-once") {
    Task.detached {
        let report = await FranklinConsciousnessActor.shared.runConsciousnessPreflight()
        if let data = try? JSONEncoder().encode(report),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
        exit(0)
    }
    RunLoop.main.run()
}

let actor = FranklinConsciousnessActor.shared
Task {
    await actor.awaken()
}
RunLoop.main.run()
