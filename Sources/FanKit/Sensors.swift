import Foundation

/// A fan's live state.
public struct FanReading: Sendable, Hashable, Identifiable {
    public let index: Int
    public let name: String
    public let rpm: Double
    public let minimumRPM: Double
    /// The maximum the SMC lists, which is as fast as macOS runs the fan.
    public let listedMaximumRPM: Double
    /// The fastest Fan Control runs the fan: its measured top speed where one is known
    /// (see `TopSpeeds`), otherwise the listed maximum.
    public let maximumRPM: Double
    public let isManual: Bool

    public var id: Int { index }

    /// Where the fan sits within its range, 0...1.
    public var fraction: Double { fraction(ofRPM: rpm) }

    /// The RPM a curve speed (0...1) stands for on this fan. Speeds up to
    /// `FanCurve.listedMaximumSpeed` span the minimum to the listed maximum, and the rest
    /// span whatever lies between the listed maximum and the fan's top speed.
    public func rpm(atSpeed speed: Double) -> Double {
        let speed = speed.clamped(to: 0...1)
        let knee = FanCurve.listedMaximumSpeed
        return speed <= knee
            ? minimumRPM + (listedMaximumRPM - minimumRPM) * speed / knee
            : listedMaximumRPM + (maximumRPM - listedMaximumRPM) * (speed - knee) / (1 - knee)
    }

    /// Where a curve speed (0...1) puts the fan within its range, 0...1.
    public func fraction(atSpeed speed: Double) -> Double { fraction(ofRPM: rpm(atSpeed: speed)) }

    private func fraction(ofRPM rpm: Double) -> Double {
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

    /// This Mac's model identifier, e.g. "MacBookPro16,1".
    public static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }()

    public static func fanCount(_ smc: SMC) -> Int {
        Int(smc.number("FNum") ?? 0)
    }

    public static func fans(_ smc: SMC) -> [FanReading] {
        let count = fanCount(smc)
        let forcedMask = Int(smc.number("FS! ") ?? 0)
        return (0..<count).compactMap { i in
            guard let rpm = smc.number(.fan(i, "Ac")) else { return nil }
            let mode = smc.number(.fan(i, "Md"))
            let listedMaximum = smc.number(.fan(i, "Mx")) ?? 0
            return FanReading(
                index: i,
                name: fanName(i, count: count),
                rpm: max(rpm, 0),
                minimumRPM: smc.number(.fan(i, "Mn")) ?? 0,
                listedMaximumRPM: listedMaximum,
                maximumRPM: TopSpeeds.topSpeed(fan: i, of: count, listedMaximum: listedMaximum),
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
