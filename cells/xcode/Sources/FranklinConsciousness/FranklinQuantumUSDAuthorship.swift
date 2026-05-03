import Foundation

/// P1‑001: USD stage authorship declarations for **`/World/Quantum/*`** — serialized for RealityKit / operator tooling (**no GRDB row** for ProjectionProbe).
public enum FranklinQuantumUSDAuthorship {
    public struct QuantumPrimUSD: Codable, Sendable {
        public let prim_path: String
        public let game_id: String?
        public let algorithm_count: Int?
        public let prim_role: String?
        public let constitutional_threshold_calorie: Double?
        public let constitutional_threshold_cure: Double?
        public let max_bond_dim: Double?
        public let chsh_threshold: Double?
        public let algorithms: String?
        public let max_trotter_steps: Double?
        public let max_graph_nodes: Double?
        public let max_photons: Double?
        public let max_modes: Double?
        public let max_lattice: Double?
        public let max_braid_depth: Double?
    }

    /// Seven paths — six algorithm families + ProjectionProbe (geometry only).
    public static let wakeCatalog: [QuantumPrimUSD] = [
        QuantumPrimUSD(
            prim_path: "/World/Quantum/CircuitFamily",
            game_id: "QC-CIRCUIT-001",
            algorithm_count: 5,
            prim_role: nil,
            constitutional_threshold_calorie: 0.85,
            constitutional_threshold_cure: 0.60,
            max_bond_dim: 1024,
            chsh_threshold: 2.01,
            algorithms: "Shor,Grover,QFT,QPE,AmplitudeAmplification",
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: nil,
            max_modes: nil,
            max_lattice: nil,
            max_braid_depth: nil
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/VariationalFamily",
            game_id: "QC-VARIATIONAL-001",
            algorithm_count: 4,
            prim_role: nil,
            constitutional_threshold_calorie: 0.80,
            constitutional_threshold_cure: 0.55,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: "VQE,QAOA,VariationalClassifier,QuantumAnnealing",
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: nil,
            max_modes: nil,
            max_lattice: nil,
            max_braid_depth: nil
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/LinearAlgebraFamily",
            game_id: "QC-LINALG-001",
            algorithm_count: 3,
            prim_role: nil,
            constitutional_threshold_calorie: 0.70,
            constitutional_threshold_cure: 0.40,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: "HHL,QSVT,qPCA",
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: nil,
            max_modes: nil,
            max_lattice: nil,
            max_braid_depth: nil
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/SimulationFamily",
            game_id: "QC-SIMULATION-001",
            algorithm_count: 2,
            prim_role: nil,
            constitutional_threshold_calorie: 0.82,
            constitutional_threshold_cure: 0.58,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: "QuantumWalk,HamiltonianSimulation",
            max_trotter_steps: 10,
            max_graph_nodes: 16,
            max_photons: nil,
            max_modes: nil,
            max_lattice: nil,
            max_braid_depth: nil
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/BosonicFamily",
            game_id: "QC-BOSONIC-001",
            algorithm_count: 2,
            prim_role: nil,
            constitutional_threshold_calorie: 0.88,
            constitutional_threshold_cure: 0.65,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: "BosonSampling,GaussianBosonSampling",
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: 3,
            max_modes: 4,
            max_lattice: nil,
            max_braid_depth: nil
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/ErrorCorrectionFamily",
            game_id: "QC-ERRORCORR-001",
            algorithm_count: 3,
            prim_role: nil,
            constitutional_threshold_calorie: 0.75,
            constitutional_threshold_cure: 0.45,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: "SteaneCode,SurfaceCode,TopologicalQEC",
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: nil,
            max_modes: nil,
            max_lattice: 3,
            max_braid_depth: 8
        ),
        QuantumPrimUSD(
            prim_path: "/World/Quantum/ProjectionProbe",
            game_id: "QUANTUM-PROOF-001",
            algorithm_count: nil,
            prim_role: "proof_injection_surface",
            constitutional_threshold_calorie: nil,
            constitutional_threshold_cure: nil,
            max_bond_dim: nil,
            chsh_threshold: nil,
            algorithms: nil,
            max_trotter_steps: nil,
            max_graph_nodes: nil,
            max_photons: nil,
            max_modes: nil,
            max_lattice: nil,
            max_braid_depth: nil
        ),
    ]

    public static let wakeSubject = "gaiaftcl.franklin.quantum.usd.prim"

    public static func publishWakeCatalog(to bridge: NATSBridge) async {
        for prim in wakeCatalog {
            await bridge.publishJSON(subject: wakeSubject, payload: prim)
        }
    }
}
