import CSMC
import Foundation

/// Holds the fans at a fixed speed, or gives them back to macOS.
///
/// Apple silicon: `Ftst = 1` stops thermalmonitord from driving the fans, then each fan goes to
/// manual mode (`F<n>Md = 1`) with a target speed (`F<n>Tg`). macOS may take a moment to let go,
/// so the mode write is retried. Intel Macs have no `Ftst` and take the mode right away.
enum FanControl {
    /// Returns an error message, or nil.
    static func hold(level: Double) -> String? {
        let level = min(max(level, 0), 1)
        let count = fanCount()
        guard count > 0 else { return "This Mac has no fans." }
        if hasKey("Ftst"), !write("Ftst", uint8: 1) { return "The SMC refused fan control." }
        for fan in 0..<count {
            guard setManual(fan) else {
                _ = release()
                return "macOS didn't hand over fan \(fan + 1)."
            }
            let low = readFloat("F\(fan)Mn") ?? 0, high = readFloat("F\(fan)Mx") ?? 0
            guard high > low, write("F\(fan)Tg", float: low + Float(level) * (high - low)) else {
                _ = release()
                return "Couldn't set the speed of fan \(fan + 1)."
            }
        }
        return nil
    }

    static func release() -> String? {
        var ok = true
        for fan in 0..<fanCount() where hasKey("F\(fan)Md") {
            ok = write("F\(fan)Md", uint8: 0) && ok
        }
        if hasKey("Ftst") { ok = write("Ftst", uint8: 0) && ok }
        return ok ? nil : "Couldn't give the fans back to macOS."
    }

    static func releaseIfHeld() {
        let held = readUInt8("Ftst") == 1 || (0..<fanCount()).contains { readUInt8("F\($0)Md") == 1 }
        if held { _ = release() }
    }

    private static func setManual(_ fan: Int) -> Bool {
        for _ in 0..<40 {
            if write("F\(fan)Md", uint8: 1), readUInt8("F\(fan)Md") == 1 { return true }
            usleep(100_000)
        }
        return false
    }

    // MARK: SMC

    private static func fanCount() -> Int { Int(readUInt8("FNum") ?? 0) }

    private static func read(_ key: String) -> (bytes: [UInt8], type: String)? {
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0, type: UInt32 = 0
        guard lamba_smc_read_key(key, &bytes, &size, &type) == LAMBA_SMC_OK else { return nil }
        let name = String(bytes: [24, 16, 8, 0].map { UInt8((type >> $0) & 0xff) }, encoding: .ascii) ?? ""
        return (Array(bytes.prefix(Int(size))), name)
    }

    private static func hasKey(_ key: String) -> Bool { read(key) != nil }
    private static func readUInt8(_ key: String) -> UInt8? { read(key)?.bytes.first }

    private static func readFloat(_ key: String) -> Float? {
        guard let (bytes, type) = read(key) else { return nil }
        if type == "flt ", bytes.count == 4 { return bytes.withUnsafeBytes { $0.load(as: Float.self) } }
        if type == "fpe2", bytes.count == 2 { return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4 }
        return nil
    }

    private static func write(_ key: String, uint8 value: UInt8) -> Bool {
        lamba_smc_write_key(key, [value], 1) == LAMBA_SMC_OK
    }

    private static func write(_ key: String, float value: Float) -> Bool {
        guard let type = read(key)?.type else { return false }
        if type == "fpe2" {
            let fixed = UInt16(max(0, value) * 4)
            return lamba_smc_write_key(key, [UInt8(fixed >> 8), UInt8(fixed & 0xff)], 2) == LAMBA_SMC_OK
        }
        let bytes = withUnsafeBytes(of: value) { Array($0) }
        return lamba_smc_write_key(key, bytes, 4) == LAMBA_SMC_OK
    }
}
