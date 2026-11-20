import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusMenu: StatusMenuController?
    private lazy var settings = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusMenu = StatusMenuController(model: model)
        statusMenu.openSettings = { [weak self] in self?.settings.show() }
        model.onDisplayChange = { [weak statusMenu] in statusMenu?.update() }
        self.statusMenu = statusMenu
        model.startRefreshing(fast: false)
        #if DEBUG
        // Snapshot runs must not take the fans away from a running copy of the app.
        if ProcessInfo.processInfo.environment["FANCONTROL_SNAPSHOT"] != nil {
            statusMenu.runDebugSnapshotIfRequested()
            return
        }
        #endif
        Task { await model.restoreSavedProfile() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight shows Settings, as menu bar apps do.
        settings.show()
        return false
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
