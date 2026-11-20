import Foundation

/// How fast fans really spin, for the models where that has been measured.
///
/// The maximum the SMC lists for a fan (`F0Mx`) is only where macOS stops: the SMC accepts
/// higher targets and the fan follows them. Speeds here were found with `sudo fanctl
/// top-speed` and set a little under where the fastest-saturating fan stops gaining, so
/// the fans can still hold their targets, and in the same ratio as the listed maximums,
/// which keeps the fans as far apart in pitch as macOS runs them.
public enum TopSpeeds {
    /// RPM per fan, in SMC order, by model identifier.
    static let measured: [String: [Double]] = [
        // Left 7797 and right 7900 rpm at 100 % drive; listed 5297 and 4905.
        "MacBookPro16,1": [7600, 7040],
    ]

    /// The fastest fan `index` of this Mac's `fanCount` should be asked to spin: its measured
    /// top speed, or the SMC's listed maximum where none has been measured.
    public static func topSpeed(fan index: Int, of fanCount: Int, listedMaximum: Double) -> Double {
        guard let speeds = measured[ThermalSensors.modelIdentifier], speeds.count == fanCount,
              speeds.indices.contains(index) else {
            return listedMaximum
        }
        return max(listedMaximum, speeds[index])
    }
}
