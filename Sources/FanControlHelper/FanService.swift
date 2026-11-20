import FanKit
import Foundation
import os

let log = Logger(subsystem: HelperConstants.helperLabel, category: "service")

/// Runs the fan control loop. All state is confined to `queue`.
final class FanService {
    let queue = DispatchQueue(label: "\(HelperConstants.helperLabel).control")
    private let smc: SMC
    private let writer: FanWriter
    private var controller: CurveController?
    private var owner: ObjectIdentifier?
    private var timer: DispatchSourceTimer?
    private var lastTick: Date?
    private var lastWritten: [Int: Double] = [:]

    static let tickInterval: TimeInterval = 1

    init() throws {
        smc = try SMC()
        writer = FanWriter(smc: smc)
    }

    /// Starts following `curve` on behalf of `client`. Any other client loses control.
    func follow(_ curve: FanCurve, for client: ObjectIdentifier) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard curve.isValid else { throw HelperError("The fan curve is invalid.") }
        guard ThermalSensors.fanCount(smc) > 0 else { throw HelperError("This Mac has no controllable fans.") }

        // A fresh controller starts at the curve's speed for the current temperature;
        // the fans' own spin-up and spin-down soften the change.
        controller = CurveController(curve: curve)
        owner = client
        lastTick = nil
        log.info("Following new curve with \(curve.points.count) points")
        tick()
        startTimer()
    }

    /// Hands the fans back to macOS.
    func restoreAutomatic() {
        dispatchPrecondition(condition: .onQueue(queue))
        timer?.cancel()
        timer = nil
        controller = nil
        owner = nil
        lastWritten = [:]
        for fan in 0..<ThermalSensors.fanCount(smc) {
            do { try writer.restoreAutomatic(fan: fan) } catch { log.error("Restore fan \(fan) failed: \(String(describing: error))") }
        }
        log.info("Fans returned to automatic control")
    }

    func clientDisconnected(_ client: ObjectIdentifier) {
        dispatchPrecondition(condition: .onQueue(queue))
        if owner == client { restoreAutomatic() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard var controller else { return }
        let now = Date()
        // After sleep the gap can be long; cap it so ramps don't jump.
        let interval = lastTick.map { min(now.timeIntervalSince($0), 5) } ?? Self.tickInterval
        lastTick = now

        let snapshot = ThermalSensors.read(smc)
        // Without a temperature reading, fail safe: full speed.
        let speed = snapshot.controlTemperature.map { controller.update(temperature: $0, interval: interval) } ?? 1
        self.controller = controller

        for fan in snapshot.fans {
            let rpm = (fan.minimumRPM + (fan.maximumRPM - fan.minimumRPM) * speed).rounded()
            // Rewrite when the target moves meaningfully, or when something (e.g. waking from
            // sleep) has put the fan back in automatic mode.
            let stale = lastWritten[fan.index].map { abs($0 - rpm) >= 15 } ?? true
            guard stale || !writer.isForced(fan: fan.index) else { continue }
            do {
                try writer.setSpeed(fan: fan.index, rpm: rpm)
                lastWritten[fan.index] = rpm
            } catch {
                log.error("Setting \(fan.name) to \(rpm) rpm failed: \(String(describing: error))")
            }
        }
    }
}

struct HelperError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
