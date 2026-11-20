import AppKit
import FanKit
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: HelperConstants.appIdentifier, category: "model")

/// App state shared by the menu bar item and the Settings window.
@MainActor
@Observable
final class AppModel {
    private(set) var profile: FanProfile = .automatic
    private(set) var snapshot = ThermalSnapshot()
    private(set) var helperInstalled = false
    /// True while a profile change is waiting on the helper or the password prompt.
    private(set) var isApplying = false

    var showsTemperatureInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showsTemperatureInMenuBar, forKey: Keys.showsTemperature)
            onDisplayChange?()
        }
    }

    var opensAtLogin: Bool {
        get { loginItemStatus == .enabled }
        set { setOpensAtLogin(newValue) }
    }
    private var loginItemStatus = SMAppService.mainApp.status

    /// Lets AppKit views refresh when something they display changes.
    @ObservationIgnored var onDisplayChange: (() -> Void)?

    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private let smc = try? SMC()
    @ObservationIgnored private var refreshTimer: Timer?

    private enum Keys {
        static let profile = "FanProfile"
        static let showsTemperature = "ShowsTemperatureInMenuBar"
    }

    init() {
        showsTemperatureInMenuBar = UserDefaults.standard.bool(forKey: Keys.showsTemperature)
        helperInstalled = helper.isInstalled
        helper.onInterrupted = { [weak self] in self?.helperDidRestart() }
        refresh()
    }

    var isSMCAvailable: Bool { smc != nil }

    // MARK: Sensors

    /// Number of open views showing live readings (the menu, the Settings window).
    @ObservationIgnored private var liveViewers = 0

    /// Call with true when a view showing readings opens and false when it closes.
    /// Readings refresh every second while anything is showing them, and lazily otherwise.
    func setLive(_ live: Bool) {
        liveViewers = max(0, liveViewers + (live ? 1 : -1))
        startRefreshing(fast: liveViewers > 0)
    }

    func startRefreshing(fast: Bool) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: fast ? 1 : 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = fast ? 0.1 : 1
        // .common keeps readings live while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    func refresh() {
        guard let smc else { return }
        let next = ThermalSensors.read(smc)
        if next != snapshot {
            snapshot = next
            onDisplayChange?()
        }
    }

    // MARK: Profiles

    /// Re-applies the saved profile at launch, without prompting for a password.
    func restoreSavedProfile() async {
        guard let saved = UserDefaults.standard.string(forKey: Keys.profile).flatMap(FanProfile.init),
              let curve = saved.curve,
              await helper.installedVersion() == HelperConstants.helperVersion else { return }
        do {
            try await helper.follow(curve)
            profile = saved
            onDisplayChange?()
        } catch {
            log.error("Couldn’t restore \(saved.name): \(error.localizedDescription)")
        }
    }

    func select(_ newProfile: FanProfile) {
        guard newProfile != profile || newProfile.curve != nil, !isApplying else { return }
        isApplying = true
        Task {
            defer {
                isApplying = false
                onDisplayChange?()
            }
            do {
                if let curve = newProfile.curve {
                    try await ensureHelper()
                    try await helper.follow(curve)
                } else {
                    await helper.restoreAutomatic()
                }
                profile = newProfile
                UserDefaults.standard.set(newProfile.rawValue, forKey: Keys.profile)
            } catch HelperClientError.cancelled {
                // The user dismissed the password prompt; keep the current profile.
            } catch {
                present(error, couldnt: "switch to \(newProfile.name)")
            }
        }
    }

    /// Installs the helper, or updates it if the app was updated since.
    private func ensureHelper() async throws {
        if await helper.installedVersion() == HelperConstants.helperVersion { return }
        try helper.install()
        helperInstalled = helper.isInstalled
        // launchd may take a moment to start the freshly loaded helper.
        for _ in 0..<20 {
            if await helper.installedVersion() == HelperConstants.helperVersion { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw HelperClientError.unreachable("It was installed but isn’t responding.")
    }

    private func helperDidRestart() {
        guard let curve = profile.curve else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            do { try await helper.follow(curve) } catch {
                log.error("Couldn’t resume after helper restart: \(error.localizedDescription)")
                profile = .automatic
                onDisplayChange?()
            }
        }
    }

    func uninstallHelper() {
        do {
            try helper.uninstall()
            profile = .automatic
            UserDefaults.standard.set(FanProfile.automatic.rawValue, forKey: Keys.profile)
        } catch HelperClientError.cancelled {
        } catch {
            present(error, couldnt: "remove the helper")
        }
        helperInstalled = helper.isInstalled
        onDisplayChange?()
    }

    /// Hands the fans back to macOS before the app exits.
    func prepareForTermination() {
        if profile.curve != nil { helper.restoreAutomaticSynchronously() }
    }

    // MARK: Login item

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            present(error, couldnt: enabled ? "add Fan Control to your login items" : "remove Fan Control from your login items")
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    // MARK: Errors

    private func present(_ error: Error, couldnt action: String) {
        log.error("Couldn’t \(action): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t \(action)."
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
