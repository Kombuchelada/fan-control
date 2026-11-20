import FanKit
import Foundation

/// Puts fans into forced mode and sets their targets. Requires root.
struct FanWriter {
    let smc: SMC

    /// Sets fan `index` to `rpm`, clamped to the fan's own limits.
    func setSpeed(fan index: Int, rpm: Double) throws {
        let minimum = smc.number(.fan(index, "Mn")) ?? 0
        let maximum = smc.number(.fan(index, "Mx")) ?? rpm
        let target = rpm.clamped(to: minimum...max(minimum, maximum))
        try setForced(fan: index, true)
        try smc.write(.fan(index, "Tg"), number: target)
    }

    func restoreAutomatic(fan index: Int) throws {
        try setForced(fan: index, false)
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

