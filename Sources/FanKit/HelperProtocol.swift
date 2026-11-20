import Foundation

public enum HelperConstants {
    /// Bundle identifier of the app, also its code-signing identifier.
    public static let appIdentifier = "app.fancontrol.FanControl"
    /// Label, Mach service name and executable name of the privileged helper.
    public static let helperLabel = "app.fancontrol.helper"
    /// Bump whenever the helper changes so the app reinstalls it.
    public static let helperVersion = "1.0.0"

    public static let installedHelperPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    public static let installedPlistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
}

/// Interface the root helper exports over XPC.
///
/// The helper runs the control loop itself; the app only tells it which curve to follow.
/// When the app's connection goes away for any reason, the helper hands the fans back to macOS.
@objc public protocol FanHelperProtocol {
    func version(reply: @escaping (String) -> Void)
    /// `curve` is a JSON-encoded `FanCurve`. Replies with nil on success or an error message.
    func follow(curve: Data, reply: @escaping (String?) -> Void)
    /// Returns every fan to system control.
    func restoreAutomatic(reply: @escaping (String?) -> Void)
}
