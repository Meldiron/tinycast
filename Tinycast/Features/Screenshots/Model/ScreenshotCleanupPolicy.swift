import Foundation

/// Which captures a bulk removal takes. A kept capture only ever leaves one at a time.
enum ScreenshotCleanupPolicy {
    static func removable(_ captures: [ScreenCapture]) -> [ScreenCapture] {
        captures.filter { !$0.isKept }
    }

    static func expired(
        _ captures: [ScreenCapture], after autoDelete: ScreenshotAutoDelete, now: Date
    ) -> [ScreenCapture] {
        guard let cutoff = autoDelete.cutoff(from: now) else { return [] }
        return removable(captures).filter { $0.capturedAt < cutoff }
    }

    /// Everything captured before `day` began, which is what "older than this day" means.
    static func before(
        _ day: Date, in captures: [ScreenCapture], calendar: Calendar
    ) -> [ScreenCapture] {
        let start = calendar.startOfDay(for: day)
        return removable(captures).filter { $0.capturedAt < start }
    }

    static func byteCount(of captures: [ScreenCapture]) -> Int64 {
        captures.reduce(0) { $0 + $1.byteCount }
    }
}
