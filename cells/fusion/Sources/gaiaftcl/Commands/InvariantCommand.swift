import ArgumentParser
import GaiaFTCLCore
import Foundation

struct InvariantCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "invariant",
        abstract: "OWL Protocol Invariant Registry",
        subcommands: [
            List.self,
            Show.self,
            Add.self,
            Promote.self,
            Close.self,
            Refuse.self,
            Census.self,
            Sign.self,
            Verify.self,
            Neuro.self,
            AntiInflammation.self,
            Pineal.self
        ]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "All registered invariants")
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            let list = await InvariantRegistry.shared.list()
            let json = try JSONEncoder().encode(list)
            let str = String(data: json, encoding: .utf8) ?? "[]"
            print("CALORIE\n{\"invariants\": \(str)}")
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Full InvariantRecord")
        @Argument(help: "Designation") var designation: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            if let record = await InvariantRegistry.shared.get(id: designation) {
                let json = try JSONEncoder().encode(record)
                let str = String(data: json, encoding: .utf8) ?? "{}"
                print("CALORIE\n\(str)")
            } else {
                print("REFUSED\n{\"error\": \"Not found\"}")
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Register new invariant")
        @Option(name: .customLong("designation")) var designation: String
        @Option(name: .customLong("name")) var name: String
        @Option(name: .customLong("type")) var type: String
        @Option(name: .customLong("source")) var source: String
        @Option(name: .customLong("epistemic-tag")) var epistemicTag: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            let record = InvariantRecord(
                invariantId: designation,
                title: name,
                domain: "custom",
                owlClassification: type,
                epistemicTag: epistemicTag,
                status: "DRAFT",
                description: ""
            )
            try await InvariantRegistry.shared.save(record)
            print("CALORIE\n{\"added\": \"\(designation)\"}")
        }
    }

    struct Promote: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "promote", abstract: "DRAFT→OPEN→CURE-PROXY")
        @Argument(help: "Designation") var designation: String
        @Option(name: .customLong("evidence")) var evidence: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            try await InvariantRegistry.shared.transitionStatus(id: designation, to: "CURE-PROXY", evidence: evidence)
            print("CURE\n{\"promoted\": \"\(designation)\"}")
        }
    }

    struct Close: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "close", abstract: "CURE-PROXY→CURE-CLOSED")
        @Argument(help: "Designation") var designation: String
        @Option(name: .customLong("closure-evidence")) var closureEvidence: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            try await InvariantRegistry.shared.transitionStatus(id: designation, to: "CURE-CLOSED", evidence: closureEvidence)
            print("CURE\n{\"closed\": \"\(designation)\"}")
        }
    }

    struct Refuse: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "refuse", abstract: "Any→REFUSED")
        @Argument(help: "Designation") var designation: String
        @Option(name: .customLong("reason")) var reason: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            try await InvariantRegistry.shared.transitionStatus(id: designation, to: "REFUSED", evidence: reason)
            print("REFUSED\n{\"refused\": \"\(designation)\"}")
        }
    }

    struct Census: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "census", abstract: "Invariant census")
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            let list = await InvariantRegistry.shared.list()
            print("CALORIE\n{\"total\": \(list.count)}")
        }
    }

    struct Sign: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "sign", abstract: "Sign invariant record")
        @Argument(help: "Designation") var designation: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            if var record = await InvariantRegistry.shared.get(id: designation) {
                try InvariantSigner.sign(&record, walletHash: "sha256:operator", cellId: "local")
                try await InvariantRegistry.shared.save(record)
                print("CURE\n{\"signed\": \"\(designation)\"}")
            } else {
                print("REFUSED\n{\"error\": \"Not found\"}")
            }
        }
    }

    struct Verify: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "verify", abstract: "Verify invariant signature")
        @Argument(help: "Designation") var designation: String
        mutating func run() async throws {
            await InvariantRegistry.shared.loadAll()
            if let record = await InvariantRegistry.shared.get(id: designation) {
                let valid = InvariantSigner.verify(record)
                let state = valid ? "CURE" : "REFUSED"
                print("\(state)\n{\"verified\": \"\(designation)\", \"valid\": \(valid)}")
            } else {
                print("REFUSED\n{\"error\": \"Not found\"}")
            }
        }
    }

    struct Neuro: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "neuro", abstract: "Neuropsychiatric invariants", subcommands: [Inv1.self, Inv2.self, Inv3.self, Closure.self])
        struct Inv1: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "inv1", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"inv1_status\": \"CURE-PROXY\"}") } }
        }
        struct Inv2: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "inv2", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"inv2_status\": \"CURE-PROXY\"}") } }
        }
        struct Inv3: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "inv3", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"inv3_status\": \"CURE-PROXY\"}") } }
        }
        struct Closure: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "closure", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"closure_status\": \"OPEN\"}") } }
        }
    }

    struct AntiInflammation: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "anti-inflammation", abstract: "Anti-inflammation invariants", subcommands: [VectorA.self, VectorB.self])
        struct VectorA: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "vector-a", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"vector_a_status\": \"CURE-PROXY\"}") } }
        }
        struct VectorB: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "vector-b", subcommands: [Status.self])
            struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"vector_b_status\": \"CURE-PROXY\"}") } }
        }
    }

    struct Pineal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "pineal", abstract: "Pineal invariant", subcommands: [Status.self])
        struct Status: AsyncParsableCommand { mutating func run() async throws { print("CALORIE\n{\"pineal_status\": \"CURE-PROXY\"}") } }
    }
}
