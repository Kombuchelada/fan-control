import AppKit
import SwiftUI

/// The Settings window: a standard toolbar-tabbed preferences window.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var model: AppModel?

    convenience init(model: AppModel) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(.pane("Fan Curve", symbol: "fan", FanCurveSettingsView(model: model)))
        tabs.addTabViewItem(.pane("Sensors", symbol: "thermometer.medium", SensorsSettingsView(model: model)))
        tabs.addTabViewItem(.pane("General", symbol: "gearshape", GeneralSettingsView(model: model)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.model = model
        window.delegate = self
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            model?.setLive(true)
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.setLive(false)
    }

    /// Keeps the window on screen when a tab changes the window's height.
    func windowDidResize(_ notification: Notification) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let constrained = window.constrainFrameRect(window.frame, to: screen)
        if constrained != window.frame { window.setFrame(constrained, display: true) }
    }

    #if DEBUG
    var tabController: NSTabViewController? { contentViewController as? NSTabViewController }
    #endif
}

private extension NSTabViewItem {
    static func pane(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = SettingsPaneController(rootView: AnyView(view))
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// Hosts one settings tab. Asks for the tab's full height, but never more than
/// the screen can show; the form scrolls if it is cut short.
private final class SettingsPaneController: NSHostingController<AnyView> {
    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredContentSize: NSSize {
        get {
            var size = super.preferredContentSize
            size.height = min(size.height, Self.maximumHeight(for: view.window))
            return size
        }
        set { super.preferredContentSize = newValue }
    }

    private static func maximumHeight(for window: NSWindow?) -> CGFloat {
        #if DEBUG
        if let limit = ProcessInfo.processInfo.environment["FANCONTROL_MAX_PANE_HEIGHT"].flatMap(Double.init) { return limit }
        #endif
        guard let screen = window?.screen ?? NSScreen.main else { return 600 }
        // Leave room for the title bar, the tab toolbar and a little breathing space.
        let chrome = window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 80
        return max(300, screen.visibleFrame.height - chrome - 40)
    }
}
