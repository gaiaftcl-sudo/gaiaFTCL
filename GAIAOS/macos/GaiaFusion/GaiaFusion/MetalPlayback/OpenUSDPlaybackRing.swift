import Foundation

/// IPC/WASM enqueues telemetry + epistemic boundary here; only Metal `draw(in:)` reads it.
final class OpenUSDPlaybackRing: @unchecked Sendable {
    private let lock = NSLock()
    private var ip: Double = 0.85
    private var bt: Double = 0.52
    private var ne: Double = 3.5e19
    /// Single-letter epistemic tags: M / T / I / A (Measurement Classification Report alignment).
    private var epIp: UInt8 = 77 // M
    private var epBt: UInt8 = 77
    private var epNe: UInt8 = 77
    /// `CALORIE` | `CURE` | `REFUSED` — viewport error tint when `REFUSED`.
    private var terminal: String = "CALORIE"

    func setTelemetry(ip: Double, bt: Double, ne: Double) {
        lock.lock()
        self.ip = ip
        self.bt = bt
        self.ne = ne
        lock.unlock()
    }

    func setEpistemicLetters(ip: String, bt: String, ne: String) {
        lock.lock()
        epIp = Self.letter(ip)
        epBt = Self.letter(bt)
        epNe = Self.letter(ne)
        lock.unlock()
    }

    func setTerminalState(_ raw: String) {
        lock.lock()
        terminal = raw.uppercased()
        lock.unlock()
    }

    func snapshotTelemetry() -> (Double, Double, Double) {
        lock.lock()
        let v = (ip, bt, ne)
        lock.unlock()
        return v
    }

    func snapshotEpistemicJSON() -> [String: Any] {
        lock.lock()
        let i = epIp
        let b = epBt
        let n = epNe
        let t = terminal
        lock.unlock()
        return [
            "I_p": Self.asciiLetter(i),
            "B_T": Self.asciiLetter(b),
            "n_e": Self.asciiLetter(n),
            "terminal": t,
        ]
    }

    var isRefusedTerminal: Bool {
        lock.lock()
        let r = terminal == "REFUSED"
        lock.unlock()
        return r
    }

    private static func asciiLetter(_ code: UInt8) -> String {
        guard code < 128 else {
            return "?"
        }
        return String(UnicodeScalar(code))
    }

    private static func letter(_ s: String) -> UInt8 {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if u.hasPrefix("T") { return 84 }
        if u.hasPrefix("I") { return 73 }
        if u.hasPrefix("A") { return 65 }
        return 77 // Measured default
    }
}
