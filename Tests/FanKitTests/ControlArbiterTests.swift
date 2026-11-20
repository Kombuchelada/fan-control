import Foundation
import Testing
@testable import FanKit

/// Several Fan Control apps (one per logged-in user) share the root helper.
@Suite struct ControlArbiterTests {
    let quiet = FanProfile.quiet.curve!
    let maximum = FanProfile.maximum.curve!
    let alice: uid_t = 501
    let bob: uid_t = 502

    @Test func appQuittingLeavesOtherAppsCurveInEffect() {
        // The reported bug: Bob's app took over, then quit (sending "automatic" on the
        // way out), and Alice's still-running app lost its curve.
        var arbiter = ControlArbiter()
        arbiter.request(maximum, session: 1, user: alice)
        arbiter.request(quiet, session: 2, user: bob)
        arbiter.request(nil, session: 2, user: bob)
        arbiter.endSession(2)
        #expect(arbiter.curve(consoleUser: alice) == maximum)
        #expect(arbiter.curve(consoleUser: nil) == maximum)
    }

    @Test func userAtTheScreenWinsOverMoreRecentBackgroundRequest() {
        var arbiter = ControlArbiter()
        arbiter.request(maximum, session: 1, user: alice)
        arbiter.request(quiet, session: 2, user: bob)
        #expect(arbiter.curve(consoleUser: alice) == maximum)
        #expect(arbiter.curve(consoleUser: bob) == quiet)
        // At the login window nobody is at the screen: the most recent request wins.
        #expect(arbiter.curve(consoleUser: nil) == quiet)
    }

    @Test func explicitAutomaticBeatsBackgroundCurve() {
        var arbiter = ControlArbiter()
        arbiter.request(maximum, session: 2, user: bob)
        arbiter.request(nil, session: 1, user: alice)
        #expect(arbiter.curve(consoleUser: alice) == nil)
    }

    @Test func fansReturnToAutomaticWhenEveryAppHasGone() {
        var arbiter = ControlArbiter()
        arbiter.request(maximum, session: 1, user: alice)
        arbiter.request(quiet, session: 2, user: bob)
        arbiter.endSession(1)
        arbiter.endSession(2)
        #expect(arbiter.curve(consoleUser: alice) == nil)
    }
}
