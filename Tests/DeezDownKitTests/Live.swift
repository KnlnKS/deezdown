import Foundation
import Testing

let liveARL = ProcessInfo.processInfo.environment["DEEZDOWN_TEST_ARL"]

extension Trait where Self == ConditionTrait {
    /// Live suites sign in to Deezer, so they run only when given an account.
    static var live: Self { .enabled(if: liveARL != nil, "set DEEZDOWN_TEST_ARL to run live Deezer tests") }
}
