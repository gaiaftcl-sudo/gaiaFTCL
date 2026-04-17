import ArgumentParser
import Foundation
import GaiaFTCLCore

struct PathogenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pathogen",
        abstract: "OWL Protocol pathogen layer (Rife cantilever / MOPA / Calm-Energy)",
        subcommands: [
            List.self,
            Show.self,
            ComputeMOR.self,
            Add.self,
            Verify.self,
            Simulate.self,
            Refuse.self,
            Emit.self,
            Invariants.self
        ]
    )

    // MARK: - list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "Enumerate pathogen records")
        @Option(name: .customLong("tag"), help: "Filter by epistemic tag (M|T|C|A|R)") var tag: String?

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            var records = await PathogenRegistry.shared.list()
            if let tag, let filter = EpistemicTag(rawValue: tag) {
                records = records.filter { $0.epistemicTag == filter }
            }
            let slim = records.map { PathogenSummary(from: $0) }
            let data = try JSONEncoder().encode(slim)
            let str = String(data: data, encoding: .utf8) ?? "[]"
            print("CALORIE\n{\"pathogens\": \(str)}")
        }
    }

    // MARK: - show

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Full PathogenRecord")
        @Argument(help: "Pathogen ID") var pathogenId: String

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            guard let record = await PathogenRegistry.shared.get(id: pathogenId) else {
                print("REFUSED\n{\"error\": \"pathogen not found: \(pathogenId)\"}")
                throw ExitCode(1)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            let str = String(data: data, encoding: .utf8) ?? "{}"
            print("CALORIE\n\(str)")
        }
    }

    // MARK: - compute-mor

    struct ComputeMOR: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "compute-mor", abstract: "Compute MOR from k and m")
        @Option(name: .customLong("k"), help: "Stiffness k in N/m") var k: Double
        @Option(name: .customLong("m"), help: "Mass m in kg") var m: Double

        mutating func run() async throws {
            let mor = MORCompute.computeMorHz(stiffnessNPerM: k, massKg: m)
            print("CURE\n{\"k_n_per_m\": \(k), \"m_kg\": \(m), \"mor_hz\": \(mor)}")
        }
    }

    // MARK: - add

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Register new pathogen (computes MOR)")
        @Option(name: .customLong("id")) var pathogenId: String
        @Option(name: .customLong("common-name")) var commonName: String
        @Option(name: .customLong("scientific-name")) var scientificName: String
        @Option(name: .customLong("kingdom")) var kingdom: String
        @Option(name: .customLong("target-kind"), help: "viral_spike|viral_capsid|viral_envelope|bacterial_cell_wall|bacterial_flagellum|fungal_cell_wall|protozoal_membrane|prion_fibril") var targetKind: String
        @Option(name: .customLong("k"), help: "Stiffness k in N/m") var stiffness: Double
        @Option(name: .customLong("m"), help: "Mass m in kg") var mass: Double
        @Option(name: .customLong("epistemic-tag"), help: "M|T|C|A") var epistemicTag: String
        @Option(name: .customLong("description")) var description: String = ""

        mutating func run() async throws {
            guard let kind = StructuralTarget.Kind(rawValue: targetKind) else {
                print("REFUSED\n{\"error\": \"invalid target-kind: \(targetKind)\"}")
                throw ExitCode(2)
            }
            guard let tag = EpistemicTag(rawValue: epistemicTag) else {
                print("REFUSED\n{\"error\": \"invalid epistemic-tag: \(epistemicTag)\"}")
                throw ExitCode(2)
            }
            await PathogenRegistry.shared.loadAll()
            let target = StructuralTarget(kind: kind, stiffnessNPerM: stiffness, massKg: mass)
            let record = try await PathogenRegistry.shared.create(
                pathogenId: pathogenId,
                commonName: commonName,
                scientificName: scientificName,
                taxonomy: Taxonomy(kingdom: kingdom),
                target: target,
                epistemicTag: tag,
                description: description
            )
            print("CURE\n{\"added\": \"\(record.pathogenId)\", \"mor_hz\": \(record.computedMorHz)}")
        }
    }

    // MARK: - verify

    struct Verify: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "verify", abstract: "Run Rife invariant suite on a pathogen + proposal")
        @Argument(help: "Pathogen ID") var pathogenId: String
        @Option(name: .customLong("carrier-hz"), help: "RF carrier frequency") var carrierHz: Double
        @Option(name: .customLong("modulator-hz"), help: "Audio modulator frequency") var modulatorHz: Double
        @Option(name: .customLong("power-w-cm2"), help: "Delivered power density (W/cm^2)") var powerWCm2: Double
        @Option(name: .customLong("ieee-mpe-w-cm2"), help: "IEEE C95.1-2019 occupational MPE (W/cm^2). Primary INV2 gate.") var ieeeMpeWCm2: Double = 0.01
        @Option(name: .customLong("thermal-ceiling-w-cm2"), help: "Thermal-damage upper bound (W/cm^2). INV2 backstop.") var thermalCeilingWCm2: Double = 10.0
        @Option(name: .customLong("tolerance-pct"), help: "Resonance tolerance percentage") var tolerancePct: Double = 0.5

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            let proposal = EmissionProposal(
                pathogenId: pathogenId,
                carrierFrequencyHz: carrierHz,
                modulatorFrequencyHz: modulatorHz,
                deliveredPowerDensityWPerCm2: powerWCm2,
                ieeeC95OccupationalMpeWPerCm2: ieeeMpeWCm2,
                thermalDamageUpperBoundWPerCm2: thermalCeilingWCm2,
                resonanceTolerancePct: tolerancePct
            )
            do {
                let verdict = try await PathogenRegistry.shared.evaluateProposal(proposal)
                let data = try JSONEncoder().encode(verdict)
                let str = String(data: data, encoding: .utf8) ?? "{}"
                print("\(verdict.terminalState.rawValue)\n\(str)")
                if verdict.terminalState != .cure {
                    throw ExitCode(1)
                }
            } catch {
                print("REFUSED\n{\"error\": \"\(error.localizedDescription)\"}")
                throw ExitCode(1)
            }
        }
    }

    // MARK: - simulate

    struct Simulate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "simulate", abstract: "Sweep carrier/modulator and report resonance score")
        @Argument(help: "Pathogen ID") var pathogenId: String
        @Option(name: .customLong("carrier-low")) var carrierLow: Double = 3.0e6
        @Option(name: .customLong("carrier-high")) var carrierHigh: Double = 4.0e6
        @Option(name: .customLong("steps")) var steps: Int = 41

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            guard let pathogen = await PathogenRegistry.shared.get(id: pathogenId) else {
                print("REFUSED\n{\"error\": \"pathogen not found\"}")
                throw ExitCode(1)
            }
            let target = pathogen.computedMorHz
            let clampedSteps = max(2, steps)
            let step = (carrierHigh - carrierLow) / Double(clampedSteps - 1)
            var samples: [[String: Double]] = []
            for i in 0..<clampedSteps {
                let carrier = carrierLow + Double(i) * step
                // Required modulator to hit MOR as upper sideband.
                let requiredModulator = target - carrier
                let reachable = requiredModulator >= pathogen.mopaBand.modulatorLowHz
                    && requiredModulator <= pathogen.mopaBand.modulatorHighHz
                samples.append([
                    "carrier_hz": carrier,
                    "required_modulator_hz": requiredModulator,
                    "reachable_in_audio_band": reachable ? 1.0 : 0.0
                ])
            }
            let payload: [String: Any] = [
                "pathogen_id": pathogenId,
                "target_mor_hz": target,
                "sweep": samples
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let str = String(data: data, encoding: .utf8) ?? "{}"
            print("CALORIE\n\(str)")
        }
    }

    // MARK: - refuse

    struct Refuse: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "refuse", abstract: "Refuse a pathogen record")
        @Argument(help: "Pathogen ID") var pathogenId: String
        @Option(name: .customLong("reason")) var reason: String

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            try await PathogenRegistry.shared.refuse(id: pathogenId, reason: reason)
            print("REFUSED\n{\"refused\": \"\(pathogenId)\", \"reason\": \"\(reason)\"}")
        }
    }

    // MARK: - emit

    struct Emit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "emit", abstract: "Emit evidence receipt for a verified proposal")
        @Argument(help: "Pathogen ID") var pathogenId: String
        @Option(name: .customLong("carrier-hz")) var carrierHz: Double
        @Option(name: .customLong("modulator-hz")) var modulatorHz: Double
        @Option(name: .customLong("power-w-cm2")) var powerWCm2: Double

        mutating func run() async throws {
            await PathogenRegistry.shared.loadAll()
            let proposal = EmissionProposal(
                pathogenId: pathogenId,
                carrierFrequencyHz: carrierHz,
                modulatorFrequencyHz: modulatorHz,
                deliveredPowerDensityWPerCm2: powerWCm2
            )
            let verdict = try await PathogenRegistry.shared.evaluateProposal(proposal)
            guard verdict.terminalState == .cure else {
                let data = try JSONEncoder().encode(verdict)
                print("REFUSED\n\(String(data: data, encoding: .utf8) ?? "{}")")
                throw ExitCode(1)
            }

            let fm = FileManager.default
            let dir = "evidence/pathogens/\(pathogenId)"
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let iso = ISO8601DateFormatter().string(from: Date())
            let receipt = EvidenceReceipt(
                receiptSha: S4C4Hash.sha256("pathogen:\(pathogenId):\(iso)"),
                terminalState: "CURE",
                timestamp: iso,
                cellId: "local",
                operatorWalletHash: "sha256:operator",
                trainingMode: false,
                command: "gaiaftcl pathogen emit \(pathogenId)",
                gateResults: GateResults(total: 3, passed: 3, failed: 0, gateIds: [
                    "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE",
                    "GFTCL-RIFE-INV2-CALM-ENERGY-BOUNDARY",
                    "GFTCL-RIFE-INV3-MOPA-HARMONIC-SIDEBAND"
                ]),
                evidencePaths: ["\(dir)/receipt_\(iso).json"]
            )
            try EvidenceEmitter.emit(receipt: receipt, to: "\(dir)/receipt_\(iso).json")
            print("CURE\n{\"emitted\": \"\(dir)/receipt_\(iso).json\"}")
        }
    }

    // MARK: - invariants (describe the 3 Rife invariants)

    struct Invariants: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "invariants", abstract: "Describe the 3 Rife OWL invariants")
        mutating func run() async throws {
            let payload: [[String: String]] = [
                ["id": "GFTCL-RIFE-INV1-CANTILEVER-RESONANCE", "title": "Cantilever Resonance Lock", "formula": "f = (1/2\u{03c0})\u{221a}(k/m)"],
                ["id": "GFTCL-RIFE-INV2-CALM-ENERGY-BOUNDARY", "title": "Calm Energy Boundary", "formula": "P_delivered < P_host_min ; h\u{03bd} < 10 eV"],
                ["id": "GFTCL-RIFE-INV3-MOPA-HARMONIC-SIDEBAND", "title": "Harmonic Sideband Integrity", "formula": "carrier \u{00b1} modulator \u{2192} MOR ; carrier \u{2208} [3,4] MHz ; tag = M"]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print("CALORIE\n\(String(data: data, encoding: .utf8) ?? "[]")")
        }
    }
}

// MARK: - slim summary for list()

private struct PathogenSummary: Codable {
    let pathogenId: String
    let commonName: String
    let scientificName: String
    let computedMorHz: Double
    let epistemicTag: String
    let status: String

    init(from record: PathogenRecord) {
        self.pathogenId = record.pathogenId
        self.commonName = record.commonName
        self.scientificName = record.scientificName
        self.computedMorHz = record.computedMorHz
        self.epistemicTag = record.epistemicTag.rawValue
        self.status = record.status
    }

    enum CodingKeys: String, CodingKey {
        case pathogenId = "pathogen_id"
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case computedMorHz = "computed_mor_hz"
        case epistemicTag = "epistemic_tag"
        case status
    }
}
