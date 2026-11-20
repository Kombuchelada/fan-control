import Foundation

/// The fan behaviors offered in the menu.
///
/// Curves are tuned for the control temperature (the hotter of the CPU and GPU dies).
/// Intel MacBook Pro processors idle around 45–55 °C, sit at 60–75 °C under everyday
/// work, and run into the 90s under sustained load before throttling near 100 °C.
public enum FanProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case quiet
    case balanced
    case performance
    case maximum

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .automatic: "Automatic"
        case .quiet: "Quiet"
        case .balanced: "Balanced"
        case .performance: "Performance"
        case .maximum: "Full Speed"
        }
    }

    /// One line shown under the name in the menu.
    public var subtitle: String {
        switch self {
        case .automatic: "Managed by macOS"
        case .quiet: "Silent until \(Self.degrees(62)), unhurried ramp"
        case .balanced: "Gentle ramp from \(Self.degrees(52))"
        case .performance: "Cools early to sustain boost clocks"
        case .maximum: "Maximum airflow at all times"
        }
    }

    /// Longer explanation for the Settings window.
    public var details: String {
        switch self {
        case .automatic:
            "The system management controller decides fan speeds, as it does without this app."
        case .quiet:
            "Fans stay at their minimum through browsing, writing and video calls, and rise slowly so short bursts of work go unheard. The processor runs warmer and may slow down sooner under long, heavy loads."
        case .balanced:
            "A steady, moderate ramp for mixed work. Brief spikes are smoothed out, and fans only slow down once temperatures have clearly dropped."
        case .performance:
            "Fans respond quickly and early, keeping the processor well below its thermal limit so it can hold higher clock speeds during builds, exports and games."
        case .maximum:
            "Every fan runs at its maximum speed regardless of temperature. Useful for cooling down quickly."
        }
    }

    /// SF Symbol for the profile.
    public var symbol: String {
        switch self {
        case .automatic: "fan.badge.automatic"
        case .quiet: "gauge.with.dots.needle.33percent"
        case .balanced: "gauge.with.dots.needle.50percent"
        case .performance: "gauge.with.dots.needle.67percent"
        case .maximum: "gauge.with.dots.needle.100percent"
        }
    }

    /// The curve the helper follows, or nil to let macOS control the fans.
    public var curve: FanCurve? {
        switch self {
        case .automatic:
            return nil
        // Up to `FanCurve.listedMaximumSpeed` (0.6) a curve stays within the speeds macOS
        // itself uses; above it, fans with a known top speed go faster than macOS runs them.
        case .quiet:
            return FanCurve(
                points: [.init(0, 0), .init(62, 0), .init(75, 0.09), .init(85, 0.24), .init(92, 0.45), .init(97, 1)],
                response: .init(riseSmoothing: 8, fallSmoothing: 20, hysteresis: 4, rampUp: 0.024, rampDown: 0.009))
        case .balanced:
            return FanCurve(
                points: [.init(0, 0), .init(52, 0), .init(65, 0.12), .init(78, 0.3), .init(88, 0.55), .init(94, 0.8), .init(97, 1)],
                response: .init(riseSmoothing: 4, fallSmoothing: 12, hysteresis: 3, rampUp: 0.05, rampDown: 0.02))
        case .performance:
            return FanCurve(
                points: [.init(0, 0.075), .init(45, 0.075), .init(58, 0.21), .init(70, 0.45), .init(80, 0.75), .init(88, 1)],
                response: .init(riseSmoothing: 1.5, fallSmoothing: 8, hysteresis: 2, rampUp: 0.15, rampDown: 0.03))
        case .maximum:
            return FanCurve(
                points: [.init(0, 1)],
                response: .init(riseSmoothing: 0, fallSmoothing: 0, hysteresis: 0, rampUp: 1, rampDown: 1))
        }
    }

    static func degrees(_ value: Double) -> String {
        Measurement(value: value, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
