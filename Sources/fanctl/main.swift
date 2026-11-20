// Diagnostic tool for the SMC. Reading works for anyone; `set` and `auto` need sudo.
//
//   fanctl status            temperatures and fans
//   fanctl keys [prefix]     dump raw SMC keys
//   fanctl set <fan> <rpm>   force a fan to a speed (sudo)
//   fanctl auto              return all fans to automatic control (sudo)
//   fanctl top-speed         measure how fast each fan really spins (sudo). Fans often go
//                            faster than the maximum the SMC lists. Steps every fan's target
//                            up from that maximum until its speed stops rising, then returns
//                            the fans to automatic control. Loud, and takes a minute or two.
//                            Choose Automatic in Fan Control first.
//   fanctl client <profile> [seconds] [--release]
//                            act as a Fan Control app: ask the installed helper to follow
//                            <profile>, stay connected for [seconds], optionally ask for
//                            automatic control as the app does when it quits, then disconnect.
//                            The helper only accepts clients signed like the app, so sign a
//                            copy of fanctl first (see scripts/check-multi-client.sh).
import FanKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("fanctl: \(message)\n".utf8))
    exit(1)
}

let smc: SMC
do { smc = try SMC() } catch { fail(String(describing: error)) }

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "status" : args.removeFirst()

func setForced(_ fan: Int, _ forced: Bool) throws {
    try smc.write(.fan(fan, "Md"), number: forced ? 1 : 0)
}

switch command {
case "status":
    let s = ThermalSensors.read(smc)
    print("CPU      ", s.cpu.map { String(format: "%.1f °C", $0) } ?? "—")
    print("Graphics ", s.gpu.map { String(format: "%.1f °C", $0) } ?? "—")
    for fan in s.fans {
        print(String(format: "%-9@ %5.0f rpm  (%4.0f–%4.0f)  %@", fan.name, fan.rpm, fan.minimumRPM, fan.maximumRPM,
                     fan.isManual ? "forced" : "auto"), "target", smc.number(.fan(fan.index, "Tg")).map { String(Int($0)) } ?? "?")
    }
case "keys":
    let prefix = args.first ?? ""
    for key in smc.allKeys() where key.description.hasPrefix(prefix) {
        guard let r = try? smc.read(key) else { continue }
        print(key, "[\(r.type)]", r.bytes.map { String(format: "%02x", $0) }.joined(separator: " "), r.number.map { String($0) } ?? "")
    }
case "set":
    guard args.count == 2, let fan = Int(args[0]), let rpm = Double(args[1]) else { fail("usage: fanctl set <fan> <rpm>") }
    do {
        try setForced(fan, true)
        try smc.write(.fan(fan, "Tg"), number: rpm)
    } catch { fail(String(describing: error)) }
case "auto":
    for fan in 0..<ThermalSensors.fanCount(smc) {
        do { try setForced(fan, false) } catch { fail(String(describing: error)) }
    }
case "top-speed":
    let fans = ThermalSensors.fans(smc)
    guard !fans.isEmpty else { fail("this Mac has no fans") }
    guard fans.allSatisfy({ !$0.isManual }) else {
        fail("a fan curve is active: choose Automatic in Fan Control (or quit it) first")
    }
    func restore() { for fan in fans { try? setForced(fan.index, false) } }
    // Don't leave the fans forced if the run is interrupted.
    var sources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { restore(); exit(130) }
        source.resume()
        sources.append(source)
    }
    func speeds() -> [Double] { fans.map { smc.number(.fan($0.index, "Ac")) ?? 0 } }
    /// Waits for the fans to stop changing speed, then averages three seconds of readings.
    func settledSpeeds() -> [Double] {
        var previous = speeds()
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 1)
            let now = speeds()
            let steady = zip(previous, now).allSatisfy { abs($1 - $0) <= $0 * 0.004 }
            previous = now
            if steady { break }
        }
        var sums = fans.map { _ in 0.0 }
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.5)
            for (i, rpm) in speeds().enumerated() { sums[i] += rpm }
        }
        return sums.map { $0 / 6 }
    }
    print("asked for (× listed maximum)   " + fans.map { $0.name.padding(toLength: 22, withPad: " ", startingAt: 0) }.joined())
    var best = fans.map { _ in 0.0 }
    var factor = 1.0
    do {
        while factor <= 2.0 {
            for fan in fans {
                try setForced(fan.index, true)
                try smc.write(.fan(fan.index, "Tg"), number: fan.listedMaximumRPM * factor)
            }
            let measured = settledSpeeds()
            let duty = fans.map { smc.number(.fan($0.index, "Dc")) }
            print(String(format: "%.2f", factor).padding(toLength: 31, withPad: " ", startingAt: 0)
                + zip(measured, duty).map { rpm, duty in
                    (String(format: "%5.0f rpm", rpm) + (duty.map { String(format: "  %3.0f%% drive", $0 * 100) } ?? ""))
                        .padding(toLength: 22, withPad: " ", startingAt: 0)
                }.joined())
            fflush(stdout)
            // Stop once no fan gained at least half a percent over its best so far.
            let gained = zip(measured, best).contains { $0 > $1 * 1.005 }
            best = zip(measured, best).map(max)
            if !gained { break }
            factor += 0.05
        }
    } catch {
        restore()
        fail(String(describing: error))
    }
    restore()
    print("\ntop speeds, model \(ThermalSensors.modelIdentifier):")
    for (fan, rpm) in zip(fans, best) {
        print(String(format: "  %@: %.0f rpm (listed maximum %.0f)", fan.name, rpm, fan.listedMaximumRPM))
    }
case "client":
    guard let name = args.first, let profile = FanProfile(rawValue: name) else {
        fail("usage: fanctl client <\(FanProfile.allCases.map(\.rawValue).joined(separator: "|"))> [seconds] [--release]")
    }
    let hold = args.dropFirst().first.flatMap(Double.init) ?? 0
    let connection = NSXPCConnection(machServiceName: HelperConstants.helperLabel, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
    connection.resume()
    guard let helper = connection.synchronousRemoteObjectProxyWithErrorHandler({ error in
        fail("couldn’t reach the helper: \(error.localizedDescription)")
    }) as? FanHelperProtocol else { fail("unexpected proxy") }
    if let curve = profile.curve {
        helper.follow(curve: try JSONEncoder().encode(curve)) { message in if let message { fail(message) } }
    } else {
        helper.restoreAutomatic { _ in }
    }
    print("client \(getpid()): requested \(name)")
    fflush(stdout)
    Thread.sleep(forTimeInterval: hold)
    if args.contains("--release") {
        helper.restoreAutomatic { _ in }
        print("client \(getpid()): requested automatic before quitting")
    }
    connection.invalidate()
default:
    fail("unknown command \(command)")
}
