import AppKit
import FanKit
import os

private let log = Logger(subsystem: HelperConstants.appIdentifier, category: "helper")

enum HelperClientError: LocalizedError {
    case unreachable(String)
    case helper(String)
    case installFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreachable(let detail): "Fan Control couldn’t reach its helper. \(detail)"
        case .helper(let message): message
        case .installFailed(let message): "The helper couldn’t be installed. \(message)"
        case .cancelled: nil
        }
    }
}

/// Talks to the privileged helper over XPC, and installs or removes it.
@MainActor
final class HelperClient {
    private var connection: NSXPCConnection?

    /// Called when the helper restarted unexpectedly and has dropped the curve it was following.
    var onInterrupted: (() -> Void)?

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperConstants.installedHelperPath)
            && FileManager.default.fileExists(atPath: HelperConstants.installedPlistPath)
    }

    // MARK: Requests

    /// The installed helper's version, or nil if it isn't running or reachable.
    func installedVersion() async -> String? {
        guard isInstalled else { return nil }
        return try? await call { helper, reply in helper.version(reply: reply) }
    }

    func follow(_ curve: FanCurve) async throws {
        let data = try JSONEncoder().encode(curve)
        let message: String? = try await call { helper, reply in helper.follow(curve: data, reply: reply) }
        if let message { throw HelperClientError.helper(message) }
    }

    func restoreAutomatic() async {
        guard connection != nil || isInstalled else { return }
        _ = try? await call { (helper: FanHelperProtocol, reply: @escaping (String?) -> Void) in
            helper.restoreAutomatic(reply: reply)
        }
    }

    /// Blocking variant for use while the app terminates.
    func restoreAutomaticSynchronously() {
        guard let connection else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as? FanHelperProtocol
        proxy?.restoreAutomatic { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 1)
    }

    private func makeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                log.notice("Helper connection interrupted")
                self?.onInterrupted?()
            }
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func call<T: Sendable>(_ body: @escaping (FanHelperProtocol, @escaping (T) -> Void) -> Void) async throws -> T {
        let connection = makeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.run { continuation.resume(throwing: HelperClientError.unreachable(error.localizedDescription)) }
            }
            guard let helper = proxy as? FanHelperProtocol else {
                once.run { continuation.resume(throwing: HelperClientError.unreachable("Unexpected proxy.")) }
                return
            }
            body(helper) { value in once.run { continuation.resume(returning: value) } }
        }
    }

    // MARK: Installation

    /// Installs (or updates) the helper. Shows the system administrator prompt.
    func install() throws {
        connection?.invalidate()
        connection = nil
        try runPrivileged("install", prompt: "Fan Control needs to install a helper to change fan speeds.")
    }

    func uninstall() throws {
        restoreAutomaticSynchronously()
        connection?.invalidate()
        connection = nil
        try runPrivileged("uninstall", prompt: "Fan Control wants to remove its fan control helper.")
    }

    private func runPrivileged(_ action: String, prompt: String) throws {
        guard let script = Bundle.main.path(forResource: "helper-tool", ofType: "sh") else {
            throw HelperClientError.installFailed("The app bundle is missing its installer script. Rebuild the app with scripts/build.sh.")
        }
        let command = ["/bin/sh", script, action, Bundle.main.bundlePath].map(\.shellQuoted).joined(separator: " ")
        let source = "do shell script \(command.appleScriptQuoted) with prompt \(prompt.appleScriptQuoted) with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // -128: the user clicked Cancel in the password prompt.
            if errorInfo[NSAppleScript.errorNumber] as? Int == -128 { throw HelperClientError.cancelled }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error."
            log.error("Privileged \(action) failed: \(message)")
            throw HelperClientError.installFailed(message)
        }
    }
}

/// Runs a closure at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

private extension String {
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
