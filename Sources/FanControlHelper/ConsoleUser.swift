import Foundation
import SystemConfiguration

/// The user at the screen, which decides whose fan curve wins when several users run Fan Control.
enum ConsoleUser {
    /// The uid of the user at the screen, or nil at the login window.
    static func current() -> uid_t? {
        var uid: uid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?,
              name != "loginwindow" else { return nil }
        return uid
    }

    /// Calls `onChange` on `queue` whenever the user at the screen changes.
    /// Keep the returned object alive for as long as you want notifications.
    static func watch(on queue: DispatchQueue, onChange: @escaping () -> Void) -> AnyObject? {
        let watcher = Watcher(onChange: onChange)
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(watcher).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "app.fancontrol.helper" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }, &context) else { return nil }
        let key = SCDynamicStoreKeyCreateConsoleUser(nil)
        guard SCDynamicStoreSetNotificationKeys(store, [key] as CFArray, nil),
              SCDynamicStoreSetDispatchQueue(store, queue) else { return nil }
        watcher.store = store
        return watcher
    }

    private final class Watcher {
        let onChange: () -> Void
        var store: SCDynamicStore?
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
    }
}
