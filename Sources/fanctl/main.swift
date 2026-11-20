// Diagnostic tool for the SMC. Reading works for anyone; `set` and `auto` need sudo.
//
//   fanctl status            temperatures and fans
//   fanctl keys [prefix]     dump raw SMC keys
//   fanctl set <fan> <rpm>   force a fan to a speed (sudo)
//   fanctl auto              return all fans to automatic control (sudo)
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
