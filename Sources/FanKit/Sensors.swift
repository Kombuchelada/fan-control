import Foundation

/// A fan's live state.
public struct FanReading: Sendable, Hashable, Identifiable {
    public let index: Int
    public let name: String
    public let rpm: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let isManual: Bool

    public var id: Int { index }

    /// Where the fan sits within its range, 0...1.
    public var fraction: Double {
        maximumRPM > minimumRPM ? ((rpm - minimumRPM) / (maximumRPM - minimumRPM)).clamped(to: 0...1) : 0
    }
}

/// A snapshot of the temperatures and fans this app cares about.
public struct ThermalSnapshot: Sendable, Hashable {
    public var cpu: Double?
    public var gpu: Double?
    public var fans: [FanReading]

    public init(cpu: Double? = nil, gpu: Double? = nil, fans: [FanReading] = []) {
        self.cpu = cpu
        self.gpu = gpu
        self.fans = fans
    }

    /// The temperature fan curves are evaluated against: the hotter of the CPU and GPU.
    public var controlTemperature: Double? {
        [cpu, gpu].compactMap { $0 }.max()
    }
}

/// Reads temperatures and fan state from the SMC. Works without privileges.
public enum ThermalSensors {
    /// Candidate keys in order of preference. Die/PECI sensors respond fastest to load.
    static let cpuKeys: [SMCKey] = ["TCXC", "TCMX", "TC0F", "TC0E", "TC0D", "TC0P", "TC0H"]
    static let gpuKeys: [SMCKey] = ["TGDD", "TG0D", "TG0P", "TG0H"]

    public static func read(_ smc: SMC) -> ThermalSnapshot {
        ThermalSnapshot(cpu: firstValid(cpuKeys, smc), gpu: firstValid(gpuKeys, smc), fans: fans(smc))
    }

    public static func fanCount(_ smc: SMC) -> Int {
        Int(smc.number("FNum") ?? 0)
    }

    public static func fans(_ smc: SMC) -> [FanReading] {
        let count = fanCount(smc)
        let forcedMask = Int(smc.number("FS! ") ?? 0)
        return (0..<count).compactMap { i in
            guard let rpm = smc.number(.fan(i, "Ac")) else { return nil }
            let mode = smc.number(.fan(i, "Md"))
            return FanReading(
                index: i,
                name: fanName(i, count: count),
                rpm: max(rpm, 0),
                minimumRPM: smc.number(.fan(i, "Mn")) ?? 0,
                maximumRPM: smc.number(.fan(i, "Mx")) ?? 0,
                isManual: mode.map { $0 == 1 } ?? (forcedMask & (1 << i) != 0))
        }
    }

    public static func fanName(_ index: Int, count: Int) -> String {
        switch count {
        case 1: "Fan"
        case 2: index == 0 ? "Left Fan" : "Right Fan"
        default: "Fan \(index + 1)"
        }
    }

    private static func firstValid(_ keys: [SMCKey], _ smc: SMC) -> Double? {
        for key in keys {
            // Unused sensors report 0 or -127; anything outside this range is not a real reading.
            if let value = smc.number(key), (5...125).contains(value) { return value }
        }
        return nil
    }
}
