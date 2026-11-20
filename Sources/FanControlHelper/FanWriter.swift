import FanKit
import Foundation

/// Puts fans into forced mode and sets their targets. Requires root.
struct FanWriter {
    let smc: SMC

    /// Sets fan `index` to `rpm`, clamped to `limits`, the slowest and fastest it may run.
    func setSpeed(fan index: Int, rpm: Double, limits: ClosedRange<Double>) throws {
        try setForced(fan: index, true)
        try smc.write(.fan(index, "Tg"), number: rpm.clamped(to: limits))
    }

    func restoreAutomatic(fan index: Int) throws {
        try setForced(fan: index, false)
    }

    /// The speed fan `index` is currently set to aim for.
    func target(fan index: Int) -> Double? {
        smc.number(.fan(index, "Tg"))
    }

    func isForced(fan index: Int) -> Bool {
        if let mode = smc.number(.fan(index, "Md")) { return mode == 1 }
        return Int(smc.number("FS! ") ?? 0) & (1 << index) != 0
    }

    private func setForced(fan index: Int, _ forced: Bool) throws {
        guard isForced(fan: index) != forced else { return }
        let modeKey = SMCKey.fan(index, "Md")
        if (try? smc.read(modeKey)) != nil {
            try smc.write(modeKey, number: forced ? 1 : 0)
        } else {
            // Older Intel Macs use a bitmask of forced fans instead of a per-fan mode key.
            var mask = Int(smc.number("FS! ") ?? 0)
            mask = forced ? mask | (1 << index) : mask & ~(1 << index)
            try smc.write("FS! ", number: Double(mask))
        }
    }
}

