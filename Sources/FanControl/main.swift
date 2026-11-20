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
        model.setRefreshRate(fast: false)
        Task { await model.restoreSavedProfile() }
        #if DEBUG
        statusMenu.runDebugSnapshotIfRequested()
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again from Finder or Spotlight shows Settings, as menu bar apps do.
        settings.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
