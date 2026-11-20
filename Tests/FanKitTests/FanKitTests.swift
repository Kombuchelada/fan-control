import Foundation
import Testing
@testable import FanKit

@Suite struct FanCurveTests {
    let curve = FanCurve(points: [.init(80, 1), .init(50, 0), .init(65, 0.5)],
                         response: .init(riseSmoothing: 0, fallSmoothing: 0, hysteresis: 3, rampUp: 1, rampDown: 1))

    @Test func interpolatesAndHoldsEnds() {
        #expect(curve.speed(at: 20) == 0)
        #expect(curve.speed(at: 50) == 0)
        #expect(abs(curve.speed(at: 57.5) - 0.25) < 1e-9)
        #expect(curve.speed(at: 65) == 0.5)
        #expect(curve.speed(at: 120) == 1)
    }

    @Test func summarizesThresholds() {
        #expect(curve.quietUntil == 50)
        #expect(curve.fullSpeedAt == 80)
    }

    @Test(arguments: FanProfile.allCases)
    func presetsAreValidAndMonotonic(profile: FanProfile) {
        guard let curve = profile.curve else { return }
        #expect(curve.isValid)
    }

    @Test func presetsTradeNoiseForCooling() {
        // At every temperature, a cooler profile never runs fans slower than a quieter one.
        let ordered: [FanProfile] = [.quiet, .balanced, .performance, .maximum]
        for temp in stride(from: 30.0, through: 100, by: 1) {
            let speeds = ordered.map { $0.curve!.speed(at: temp) }
            #expect(speeds == speeds.sorted(), "at \(temp) °C: \(speeds)")
        }
    }

    @Test func rejectsDecreasingCurves() {
        let bad = FanCurve(points: [.init(40, 0.8), .init(60, 0.2)], response: curve.response)
        #expect(!bad.isValid)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(FanProfile.balanced.curve!)
        #expect(try JSONDecoder().decode(FanCurve.self, from: data) == FanProfile.balanced.curve!)
    }
}

@Suite struct CurveControllerTests {
    func controller(hysteresis: Double = 3, rampUp: Double = 1, rampDown: Double = 1, smoothing: Double = 0) -> CurveController {
        CurveController(curve: FanCurve(
            points: [.init(50, 0), .init(70, 1)],
            response: .init(riseSmoothing: smoothing, fallSmoothing: smoothing, hysteresis: hysteresis, rampUp: rampUp, rampDown: rampDown)))
    }

    @Test func firstSampleJumpsStraightToCurve() {
        var c = controller()
        #expect(abs(c.update(temperature: 60, interval: 1) - 0.5) < 1e-9)
    }

    @Test func hysteresisHoldsSpeedOnSmallDrops() {
        var c = controller(hysteresis: 3)
        _ = c.update(temperature: 60, interval: 1)          // 0.5
        #expect(abs(c.update(temperature: 58, interval: 1) - 0.5) < 1e-9) // within deadband
        #expect(abs(c.update(temperature: 55, interval: 1) - 0.4) < 1e-9) // follows 55+3
    }

    @Test func rampsAreRateLimited() {
        var c = controller(rampUp: 0.1, rampDown: 0.05)
        _ = c.update(temperature: 50, interval: 1)
        #expect(abs(c.update(temperature: 70, interval: 1) - 0.1) < 1e-9)
        #expect(abs(c.update(temperature: 70, interval: 2) - 0.3) < 1e-9)
        #expect(abs(c.update(temperature: 30, interval: 1) - 0.25) < 1e-9)
    }

    @Test func smoothingIgnoresBriefSpikes() {
        var c = controller(smoothing: 10)
        _ = c.update(temperature: 50, interval: 1)
        let spike = c.update(temperature: 90, interval: 1)
        #expect(spike < 0.3)
    }

    @Test func safetyOverridesQuietCurves() {
        var c = CurveController(curve: FanCurve(points: [.init(0, 0)],
                                                response: .init(riseSmoothing: 30, fallSmoothing: 30, hysteresis: 0, rampUp: 0.01, rampDown: 0.01)))
        _ = c.update(temperature: 99, interval: 1)
        var speed = 0.0
        for _ in 0..<10 { speed = c.update(temperature: 99, interval: 1) }
        #expect(speed > 0.99)
    }
}
