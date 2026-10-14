import Foundation

struct OutageEvent {
    let start: Date
    var end: Date?

    var durationSeconds: Double? {
        guard let end else { return nil }
        return end.timeIntervalSince(start)
    }
}
