import Foundation

/// Turns a stream of temperature samples into a smooth fan speed that follows a curve.
///
/// Pure and deterministic so it can be unit-tested; the helper calls `update` about once a second.
public struct CurveController: Sendable {
    public let curve: FanCurve

    /// Filtered temperature the curve is evaluated at.
    public private(set) var smoothedTemperature: Double?
    /// Quickly filtered temperature for the safety override.
    public private(set) var safetyTemperature: Double?
    /// Current output speed (0...1) before the safety override.
    public private(set) var level: Double?

    /// Regardless of the chosen curve, fans ramp from minimum at `safetyStart`
    /// to full speed at `safetyFull`, so no curve can let the machine cook.
    public static let safetyStart = 90.0
    public static let safetyFull = 97.0

    public init(curve: FanCurve) {
        self.curve = curve
    }

    /// Feeds a temperature sample taken `interval` seconds after the previous one
    /// and returns the fan speed (0...1) to apply.
    public mutating func update(temperature: Double, interval: Double) -> Double {
        let r = curve.response
        let smoothed = Self.filter(smoothedTemperature, toward: temperature, interval: interval,
                                   timeConstant: temperature > (smoothedTemperature ?? temperature) ? r.riseSmoothing : r.fallSmoothing)
        smoothedTemperature = smoothed
        let safetyTemp = Self.filter(safetyTemperature, toward: temperature, interval: interval, timeConstant: 1.5)
        safetyTemperature = safetyTemp

        // Speed up as soon as the curve calls for it, but only slow down once the
        // temperature has fallen `hysteresis` degrees below where that speed is called for.
        let rising = curve.speed(at: smoothed)
        let falling = curve.speed(at: smoothed + r.hysteresis)
        let current = level ?? rising
        let desired = rising > current ? rising : (falling < current ? falling : current)

        let next: Double
        if level == nil {
            next = desired
        } else if desired > current {
            next = min(desired, current + r.rampUp * interval)
        } else {
            next = max(desired, current - r.rampDown * interval)
        }
        level = next

        let span = Self.safetyFull - Self.safetyStart
        let safety = ((safetyTemp - Self.safetyStart) / span).clamped(to: 0...1)
        return max(next, safety)
    }

    /// Exponential moving average with a time constant, independent of sample rate.
    static func filter(_ previous: Double?, toward sample: Double, interval: Double, timeConstant: Double) -> Double {
        guard let previous, timeConstant > 0 else { return sample }
        let alpha = 1 - exp(-max(interval, 0) / timeConstant)
        return previous + (sample - previous) * alpha
    }
}
