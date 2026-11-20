import Foundation

/// Decides which curve the helper follows when several Fan Control apps are connected,
/// one per logged-in user.
///
/// Each connected app holds one request: a curve, or nil for automatic control. The
/// request of the user at the screen wins; among a user's requests, or when nobody is at
/// the screen, the most recent wins. An app that disconnects withdraws only its own
/// request, so the fans fall back to whatever the remaining apps asked for, and return
/// to automatic control only when no app wants anything else.
public struct ControlArbiter: Sendable {
    private struct Request {
        var curve: FanCurve?
        var user: uid_t
        var order: Int
    }

    private var requests: [Int: Request] = [:]
    private var counter = 0

    public init() {}

    /// Records `curve` (nil: automatic control) as the wish of `session`, replacing its previous one.
    public mutating func request(_ curve: FanCurve?, session: Int, user: uid_t) {
        counter += 1
        requests[session] = Request(curve: curve, user: user, order: counter)
    }

    /// Withdraws the request of a session that has disconnected.
    public mutating func endSession(_ session: Int) {
        requests[session] = nil
    }

    /// The curve to follow, or nil for automatic control.
    /// - Parameter consoleUser: the user at the screen, or nil at the login window.
    public func curve(consoleUser: uid_t?) -> FanCurve? {
        let atScreen = requests.values.filter { $0.user == consoleUser }
        let candidates = atScreen.isEmpty ? Array(requests.values) : atScreen
        return candidates.max { $0.order < $1.order }?.curve
    }
}
