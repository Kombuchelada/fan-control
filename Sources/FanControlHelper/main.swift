import FanKit
import Foundation

/// Object exported to one client connection.
final class ClientSession: NSObject, FanHelperProtocol {
    let service: FanService
    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(service: FanService) { self.service = service }

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    func follow(curve: Data, reply: @escaping (String?) -> Void) {
        service.queue.async { [self] in
            do {
                let decoded = try JSONDecoder().decode(FanCurve.self, from: curve)
                try service.follow(decoded, for: id)
                reply(nil)
            } catch {
                reply(String(describing: error))
            }
        }
    }

    func restoreAutomatic(reply: @escaping (String?) -> Void) {
        service.queue.async { [self] in
            service.restoreAutomatic()
            reply(nil)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: FanService
    init(service: FanService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ClientSession(service: service)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = session
        let id = session.id
        connection.invalidationHandler = { [service] in
            service.queue.async { service.clientDisconnected(id) }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        log.info("Accepted connection from pid \(connection.processIdentifier)")
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

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: HelperConstants.helperLabel)
// Only accept connections from the Fan Control app.
listener.setConnectionCodeSigningRequirement("identifier \"\(HelperConstants.appIdentifier)\"")
listener.delegate = delegate
listener.resume()
log.info("Helper \(HelperConstants.helperVersion) listening")
dispatchMain()
