#if DEBUG
import AppKit

/// Development aid: with FANCONTROL_SNAPSHOT=<dir> set, renders the app's own menu and
/// Settings window to PNGs (no screen-recording permission needed), then quits.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(statusItemMenu: NSMenu?, button: NSStatusBarButton?, showSettings: @escaping () -> Void) {
        guard let dir = ProcessInfo.processInfo.environment["FANCONTROL_SNAPSHOT"], let menu = statusItemMenu else { return }
        let appearance = ProcessInfo.processInfo.environment["FANCONTROL_APPEARANCE"].map { NSAppearance.Name(rawValue: $0) }
        if let appearance { NSApp.appearance = NSAppearance(named: appearance) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSettings()
            captureSettingsTabs(index: 0, dir: dir) {
                // Capture the menu while it is tracking.
                let timer = Timer(timeInterval: 1.0, repeats: false) { _ in
                    for window in NSApp.windows where window.isVisible && window.className.contains("Menu") {
                        save(window, to: "\(dir)/menu.png")
                    }
                    menu.cancelTracking()
                }
                RunLoop.main.add(timer, forMode: .common)
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: (button?.bounds.maxY ?? 0) + 6), in: button)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }
    }

    /// Selects each Settings tab in turn and captures it as settings-<n>.png.
    private static func captureSettingsTabs(index: Int, dir: String, then done: @escaping () -> Void) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentViewController is NSTabViewController }),
              let tabs = window.contentViewController as? NSTabViewController,
              index < tabs.tabViewItems.count else { return done() }
        tabs.selectedTabViewItemIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            print("tab \(index) \(window.title): frame \(window.frame) fits \(visible.contains(window.frame))")
            save(window, to: "\(dir)/settings-\(index).png")
            captureSettingsTabs(index: index + 1, dir: dir, then: done)
        }
    }

    private typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func save(_ window: NSWindow, to path: String) {
        // Ask the window server for our own window's pixels (includes remote-rendered menu content).
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let capture = unsafeBitCast(sym, to: CaptureFn.self)
            // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1
            if let image = capture(.null, 8, UInt32(truncatingIfNeeded: window.windowNumber), 1)?.takeRetainedValue() {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("captured \(window.className) → \(path)")
                return
            }
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("snapshot \(window.className) → \(path)")
    }
}
#endif
