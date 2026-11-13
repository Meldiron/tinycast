import Foundation

/// One day's captures, newest first; `start` is its first cell's flat selection index.
struct ScreenshotSection: Identifiable, Sendable {
    let day: Date
    let title: String
    let captures: [ScreenCapture]
    let start: Int

    var id: Date { day }
    var byteCount: Int64 { ScreenshotCleanupPolicy.byteCount(of: captures) }

    /// `captures` must already be newest first; the scanner sorts them that way.
    static func sections(
        of captures: [ScreenCapture], now: Date, calendar: Calendar, locale: Locale
    ) -> [ScreenshotSection] {
        var sections: [ScreenshotSection] = []
        var start = 0
        var index = captures.startIndex
        while index < captures.endIndex {
            let day = calendar.startOfDay(for: captures[index].capturedAt)
            let end = captures[index...].firstIndex {
                calendar.startOfDay(for: $0.capturedAt) != day
            } ?? captures.endIndex
            sections.append(
                ScreenshotSection(
                    day: day, title: title(for: day, now: now, calendar: calendar, locale: locale),
                    captures: Array(captures[index..<end]), start: start))
            start += end - index
            index = end
        }
        return sections
    }

    /// Today and Yesterday by name, the rest of the week by weekday, anything older by date.
    static func title(for day: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch days {
        case ...0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        case 2...6: return day.formatted(style.weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            let date = style.day().month(.wide)
            return day.formatted(sameYear ? date : date.year())
        }
    }
}
