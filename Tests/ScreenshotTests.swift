import Foundation

@main
@MainActor
struct ScreenshotTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()

    static let locale = Locale(identifier: "en_US")

    /// Friday 13 November 2026, 11:00 in Prague.
    static let now = calendar.date(
        from: DateComponents(year: 2026, month: 11, day: 13, hour: 11))!

    static func capture(
        _ name: String, hoursAgo: Double, kind: ScreenCapture.Kind = .screenshot, kept: Bool = false,
        bytes: Int64 = 1_000
    ) -> ScreenCapture {
        ScreenCapture(
            url: URL(filePath: "/Users/test/Desktop/\(name)"), kind: kind,
            capturedAt: now.addingTimeInterval(-hoursAgo * 3_600), byteCount: bytes, isKept: kept)
    }

    static func main() {
        sections()
        titles()
        search()
        cleanup()
        settings()
        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("ScreenshotTests passed")
    }

    static func sections() {
        let captures = [
            capture("a.png", hoursAgo: 1),
            capture("b.png", hoursAgo: 2),
            capture("c.png", hoursAgo: 20),
            capture("d.mov", hoursAgo: 30, kind: .recording),
            capture("e.png", hoursAgo: 24 * 40)
        ]
        let sections = ScreenshotSection.sections(
            of: captures, now: now, calendar: calendar, locale: locale)
        expect(sections.map(\.title) == ["Today", "Yesterday", "October 4"], "one section per day")
        expect(sections.map(\.captures.count) == [2, 2, 1], "captures land on their own day")
        expect(sections.map(\.start) == [0, 2, 4], "starts index the flat order")
        expect(sections[1].byteCount == 2_000, "a section totals its bytes")
        expect(
            ScreenshotSection.sections(of: [], now: now, calendar: calendar, locale: locale).isEmpty,
            "no captures, no sections")
    }

    static func titles() {
        func title(daysAgo: Int) -> String {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            return ScreenshotSection.title(for: day, now: now, calendar: calendar, locale: locale)
        }
        expect(title(daysAgo: 0) == "Today", "today by name")
        expect(title(daysAgo: 1) == "Yesterday", "yesterday by name")
        expect(title(daysAgo: 2) == "Wednesday", "this week by weekday")
        expect(title(daysAgo: 6) == "Saturday", "six days back is still a weekday")
        expect(title(daysAgo: 7) == "November 6", "a week back is a date")
        expect(title(daysAgo: 400) == "October 9, 2025", "another year carries the year")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        expect(
            ScreenshotSection.title(for: tomorrow, now: now, calendar: calendar, locale: locale)
                == "Today",
            "a clock that moved back never shows a future day")
    }

    static func search() {
        let captures = [
            capture("Snímek obrazovky 2026-11-13 v 10.52.44.png", hoursAgo: 1),
            capture("Screenshot 2026-11-12 at 09.00.00.png", hoursAgo: 26, kept: true),
            capture("Screen Recording 2026-11-12.mov", hoursAgo: 27, kind: .recording)
        ]
        func names(_ query: String, _ filter: ScreenshotFilter = .all) -> [String] {
            ScreenshotQuery.filter(captures, query: query, by: filter) { capture in
                capture.name.hasPrefix("Screenshot") ? ["Yesterday", "invoice total 42"] : []
            }.map(\.name)
        }
        expect(names("").count == 3, "an empty query keeps everything")
        expect(names("snimek").count == 1, "diacritics fold away")
        expect(names("SCREEN").count == 2, "case folds away")
        expect(names("invoice yesterday") == ["Screenshot 2026-11-12 at 09.00.00.png"], "every word")
        expect(names("total invoice").count == 1, "words match in any order")
        expect(names("invoice nope").isEmpty, "a missing word rejects")
        expect(names("", .recordings) == ["Screen Recording 2026-11-12.mov"], "recordings filter")
        expect(names("", .screenshots).count == 2, "screenshots filter")
        expect(names("", .kept) == ["Screenshot 2026-11-12 at 09.00.00.png"], "kept filter")
        expect(names("recording", .screenshots).isEmpty, "the filter answers before the query")
        expect(ScreenshotQuery.terms(in: "  a \n b  ") == ["a", "b"], "whitespace splits terms")
    }

    static func cleanup() {
        let captures = [
            capture("new.png", hoursAgo: 2),
            capture("old.png", hoursAgo: 24 * 10),
            capture("old-kept.png", hoursAgo: 24 * 10, kept: true),
            capture("ancient.mov", hoursAgo: 24 * 40, kind: .recording)
        ]
        let week = ScreenshotCleanupPolicy.expired(captures, after: .week, now: now).map(\.name)
        expect(week == ["old.png", "ancient.mov"], "a week's cutoff takes older, unkept captures")
        expect(
            ScreenshotCleanupPolicy.expired(captures, after: .never, now: now).isEmpty,
            "never expires nothing")
        let month = ScreenshotCleanupPolicy.expired(captures, after: .month, now: now).map(\.name)
        expect(month == ["ancient.mov"], "a month's cutoff spares ten-day-old captures")
        expect(
            ScreenshotCleanupPolicy.removable(captures).allSatisfy { !$0.isKept },
            "bulk removal never takes a kept capture")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let before = ScreenshotCleanupPolicy.before(yesterday, in: captures, calendar: calendar)
        expect(before.map(\.name) == ["old.png", "ancient.mov"], "older than a day starts at midnight")
        expect(ScreenshotCleanupPolicy.byteCount(of: captures) == 4_000, "byte totals add up")
    }

    static func settings() {
        expect(ScreenshotAutoDelete(rawValue: 0) == nil, "an unset key reads as no case")
        expect(
            ScreenshotAutoDelete.allCases.map(\.rawValue) == [-1, 1, 3, 7, 14, 30],
            "persisted day counts never change")
        expect(ScreenshotAutoDelete.never.cutoff(from: now) == nil, "never has no cutoff")
        expect(
            ScreenshotAutoDelete.day.cutoff(from: now) == now.addingTimeInterval(-86_400),
            "a day's cutoff is 24 hours back")
        expect(
            ScreenshotAfterUse.allCases.map(\.rawValue) == ["keep", "moveToTrash"],
            "persisted after-use tokens never change")
        expect(ScreenshotAfterUse.keep.opposite == .moveToTrash, "⌃⌘↵ trashes when ↵ keeps")
        expect(ScreenshotAfterUse.moveToTrash.opposite == .keep, "⌃⌘↵ keeps when ↵ trashes")
        expect(ScreenshotFilter.allCases.first == .all, "All Captures is the default row")
    }
}
