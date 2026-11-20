import FanKit
import Foundation

/// Object exported to one client connection: one Fan Control app, run by `user`.
final class ClientSession: NSObject, FanHelperProtocol {
    let service: FanService
    let id: Int
    let user: uid_t

    init(service: FanService, id: Int, user: uid_t) {
        self.service = service
        self.id = id
        self.user = user
    }

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func follow(curve: Data, reply: @escaping (String?) -> Void) {
        service.queue.async { [self] in
            do {
                let decoded = try JSONDecoder().decode(FanCurve.self, from: curve)
                try service.request(decoded, session: id, user: user)
                reply(nil)
            } catch {
                reply(String(describing: error))
            }
        }
    }

    func restoreAutomatic(reply: @escaping (String?) -> Void) {
        service.queue.async { [self] in
            // Only this app's wish: another app's curve may still win.
            try? service.request(nil, session: id, user: user)
            reply(nil)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: FanService
    init(service: FanService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let id = service.queue.sync { service.newSession() }
        let session = ClientSession(service: service, id: id, user: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [service] in
            service.queue.async { service.endSession(id) }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        log.notice("Session \(id): pid \(connection.processIdentifier), uid \(connection.effectiveUserIdentifier)")
        return true
    }
}

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("The fan control helper must run as root.\n".utf8))
    exit(1)
}

let service: FanService
do {
    service = try FanService()
} catch {
    log.fault("Could not open the SMC: \(String(describing: error))")
    exit(1)
}

// Fans may have been left forced if a previous helper was killed abruptly.
service.queue.sync { service.restoreAutomatic() }

// Return fans to macOS whenever launchd stops us (shutdown, uninstall, update).
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: service.queue)
    source.setEventHandler {
        service.restoreAutomatic()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

// When a different user comes to the screen (fast user switching, logging in or out),
// their app's request takes priority.
let consoleWatcher = ConsoleUser.watch(on: service.queue) {
    log.notice("User at the screen changed to uid \(ConsoleUser.current().map(String.init) ?? "none", privacy: .public)")
    service.update()
}

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: HelperConstants.helperLabel)
// Only accept connections from the Fan Control app.
let requirement = ClientRequirement.current
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = delegate
listener.resume()
log.notice("Helper \(HelperConstants.helperVersion) listening; clients must satisfy: \(requirement, privacy: .public)")
dispatchMain()
