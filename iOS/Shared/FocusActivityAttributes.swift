import ActivityKit
import Foundation

/// Describes the Live Activity (Dynamic Island and Lock Screen) for one focus session.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The running window; the system animates countdown and progress from these without waking the app.
        var startDate: Date
        var endDate: Date
        var total: TimeInterval
        /// Non-nil while the session is paused.
        var pausedRemaining: TimeInterval?
        var finished: Bool
    }

    var speciesID: String
    var seed: Double
}
