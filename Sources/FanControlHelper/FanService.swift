import FanKit
import Foundation
import os

let log = Logger(subsystem: HelperConstants.helperLabel, category: "service")

/// Runs the fan control loop. All state is confined to `queue`.
///
/// Every connected app (one per logged-in user) has a request in `arbiter`; the service
/// follows whichever curve the arbiter picks and re-picks whenever a request changes, an
/// app disconnects, or a different user comes to the screen.
final class FanService {
    let queue = DispatchQueue(label: "\(HelperConstants.helperLabel).control")
    private let smc: SMC
    private let writer: FanWriter
    private var arbiter = ControlArbiter()
    private var controller: CurveController?
    private var timer: DispatchSourceTimer?
    private var lastTick: Date?
    private var lastWritten: [Int: Double] = [:]
    /// Ticks left to leave the fans alone after something else changed their targets.
    private var quietTicks = 0
    private var nextSession = 0

    static let tickInterval: TimeInterval = 1
    /// Fan speed differences smaller than this aren't worth a write.
    static let rpmTolerance = 15.0
    /// How long macOS quiets the fans for when Siri opens, measured under automatic control.
    static let quietTickCount = 4

    init() throws {
        smc = try SMC()
        writer = FanWriter(smc: smc)
    }

    func newSession() -> Int {
        dispatchPrecondition(condition: .onQueue(queue))
        nextSession += 1
        return nextSession
    }

    /// Records what `session`'s app wants: a curve, or nil for automatic control.
    func request(_ curve: FanCurve?, session: Int, user: uid_t) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        if let curve {
            guard curve.isValid else { throw HelperError("The fan curve is invalid.") }
            guard ThermalSensors.fanCount(smc) > 0 else { throw HelperError("This Mac has no controllable fans.") }
        }
        log.notice("Session \(session) (uid \(user)) asked for \(curve == nil ? "automatic control" : "a curve", privacy: .public)")
        arbiter.request(curve, session: session, user: user)
        update()
    }

    /// An app disconnected (it quit, crashed, or its user logged out).
    func endSession(_ session: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.notice("Session \(session) ended")
        arbiter.endSession(session)
        update()
    }

    /// Follows whichever curve the arbiter picks now. Call whenever its inputs change.
    func update() {
        dispatchPrecondition(condition: .onQueue(queue))
        let wanted = arbiter.curve(consoleUser: ConsoleUser.current())
        guard wanted != controller?.curve else { return }
        if let wanted {
            // A fresh controller starts at the curve's speed for the current temperature;
            // the fans' own spin-up and spin-down soften the change.
            controller = CurveController(curve: wanted)
            lastTick = nil
            // A newly chosen curve applies at once.
            lastWritten = [:]
            quietTicks = 0
            log.notice("Following a curve with \(wanted.points.count) points")
            tick()
            startTimer()
        } else {
            restoreAutomatic()
        }
    }

    /// Hands the fans back to macOS.
    func restoreAutomatic() {
        dispatchPrecondition(condition: .onQueue(queue))
        timer?.cancel()
        timer = nil
        controller = nil
        lastWritten = [:]
        quietTicks = 0
        for fan in 0..<ThermalSensors.fanCount(smc) {
            do { try writer.restoreAutomatic(fan: fan) } catch { log.error("Restore fan \(fan) failed: \(String(describing: error))") }
        }
        log.notice("Fans returned to automatic control")
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

        // When Siri opens, macOS quiets the fans for a few seconds by dropping their targets,
        // leaving them forced. Allow the same pause, then go back to the curve, unless it's
        // too hot to wait.
        let hot = (snapshot.controlTemperature ?? .infinity) >= CurveController.safetyStart
        if quietTicks > 0 {
            quietTicks -= 1
            if quietTicks > 0, !hot { return }
            quietTicks = 0
            lastWritten = [:]
            log.notice("Setting the fans' speeds again")
        } else if !hot, snapshot.fans.contains(where: { wasRetargeted($0.index) }) {
            quietTicks = Self.quietTickCount
            log.notice("Something else changed the fans' speeds; leaving them for \(Self.quietTickCount) seconds")
            return
        }

        for fan in snapshot.fans {
            let rpm = (fan.minimumRPM + (fan.maximumRPM - fan.minimumRPM) * speed).rounded()
            // Rewrite when the target moves meaningfully, or when the fan is no longer where
            // we put it (waking from sleep, for one, returns it to automatic mode).
            if let written = lastWritten[fan.index], abs(written - rpm) < Self.rpmTolerance,
               writer.isForced(fan: fan.index), !wasRetargeted(fan.index) { continue }
            do {
                try writer.setSpeed(fan: fan.index, rpm: rpm)
                lastWritten[fan.index] = rpm
            } catch {
                log.error("Setting \(fan.name) to \(rpm) rpm failed: \(String(describing: error))")
            }
        }
    }

    /// Whether something else has given fan `index` a different target while leaving it forced.
    private func wasRetargeted(_ index: Int) -> Bool {
        guard let written = lastWritten[index], writer.isForced(fan: index),
              let target = writer.target(fan: index) else { return false }
        return abs(target - written) >= Self.rpmTolerance
    }
}

struct HelperError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
