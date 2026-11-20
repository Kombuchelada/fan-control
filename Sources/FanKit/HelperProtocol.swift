import Foundation

public enum HelperConstants {
    /// Bundle identifier of the app, also its code-signing identifier.
    public static let appIdentifier = "app.fancontrol.FanControl"
    /// Label, Mach service name and executable name of the privileged helper.
    public static let helperLabel = "app.fancontrol.helper"
    /// Bump whenever the helper or its launchd plist changes, so the app reinstalls it.
    public static let helperVersion = "6"

    public static let installedHelperPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    public static let installedPlistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
}

/// Interface the root helper exports over XPC.
///
/// The helper runs the control loop itself; each app only says what it wants. Several apps
/// can be connected at once (one per logged-in user): the helper follows the wish of the
/// user at the screen, otherwise the most recent one. When an app's connection goes away
/// for any reason, its wish is withdrawn, and the fans return to macOS once no app wants a curve.
@objc public protocol FanHelperProtocol {
    func version(reply: @escaping (String) -> Void)
    /// `curve` is a JSON-encoded `FanCurve`. Replies with nil on success or an error message.
    func follow(curve: Data, reply: @escaping (String?) -> Void)
    /// Asks for automatic control on this app's behalf.
    func restoreAutomatic(reply: @escaping (String?) -> Void)
}
