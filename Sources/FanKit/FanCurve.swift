import Foundation

/// A temperature → fan speed curve, plus how quickly the fans should respond to it.
///
/// Speeds are fractions of each fan's own range: 0 is the fan's minimum RPM, 1 its maximum.
/// Using fractions lets one curve drive fans with different limits.
public struct FanCurve: Codable, Hashable, Sendable {
    public struct Point: Codable, Hashable, Sendable {
        /// Temperature in °C.
        public var temperature: Double
        /// Fraction of the fan's range, 0...1.
        public var speed: Double

        public init(_ temperature: Double, _ speed: Double) {
            self.temperature = temperature
            self.speed = speed
        }
    }

    /// Controls how the fans follow the curve. Slow, damped responses are quieter
    /// because the fans don't audibly surge with every brief load spike.
    public struct Response: Codable, Hashable, Sendable {
        /// Time constant (s) of the temperature filter while temperatures rise.
        public var riseSmoothing: Double
        /// Time constant (s) of the temperature filter while temperatures fall.
        public var fallSmoothing: Double
        /// The temperature must fall this many °C before fans slow down, which stops
        /// the fans from hunting up and down around a curve point.
        public var hysteresis: Double
        /// Maximum change in speed per second (fraction of range) when speeding up.
        public var rampUp: Double
        /// Maximum change in speed per second (fraction of range) when slowing down.
        public var rampDown: Double

        public init(riseSmoothing: Double, fallSmoothing: Double, hysteresis: Double, rampUp: Double, rampDown: Double) {
            self.riseSmoothing = riseSmoothing
            self.fallSmoothing = fallSmoothing
            self.hysteresis = hysteresis
            self.rampUp = rampUp
            self.rampDown = rampDown
        }
    }

    public var points: [Point]
    public var response: Response

    public init(points: [Point], response: Response) {
        self.points = points.sorted { $0.temperature < $1.temperature }
        self.response = response
    }

    /// Speed (0...1) at `temperature`, linearly interpolated between points
    /// and held flat beyond the first and last points.
    public func speed(at temperature: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if temperature <= first.temperature { return first.speed.clamped(to: 0...1) }
        if temperature >= last.temperature { return last.speed.clamped(to: 0...1) }
        for (a, b) in zip(points, points.dropFirst()) where temperature <= b.temperature {
            let span = b.temperature - a.temperature
            let t = span > 0 ? (temperature - a.temperature) / span : 1
            return (a.speed + (b.speed - a.speed) * t).clamped(to: 0...1)
        }
        return last.speed.clamped(to: 0...1)
    }

    /// The highest temperature at which the fans still run at their minimum speed.
    public var quietUntil: Double? {
        guard let first = points.first, first.speed <= 0 else { return nil }
        return points.last { $0.speed <= 0 }?.temperature
    }

    /// The lowest temperature at which the fans reach full speed.
    public var fullSpeedAt: Double? {
        points.first { $0.speed >= 1 }?.temperature
    }

    /// True when the curve's points are usable: in range, and speed never drops as temperature rises.
    public var isValid: Bool {
        guard !points.isEmpty, points.count <= 32 else { return false }
        let inRange = points.allSatisfy { (0...130).contains($0.temperature) && (0...1).contains($0.speed) }
        let monotonic = zip(points, points.dropFirst()).allSatisfy { $0.speed <= $1.speed }
        let r = response
        let sane = [r.riseSmoothing, r.fallSmoothing, r.hysteresis].allSatisfy { (0...120).contains($0) }
            && r.rampUp > 0 && r.rampDown > 0
        return inRange && monotonic && sane
    }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
