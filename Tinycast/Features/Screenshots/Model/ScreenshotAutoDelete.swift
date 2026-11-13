import Foundation

/// Days as the raw value, `never` negative so the 0 an unset key reads matches no case at all.
enum ScreenshotAutoDelete: Int, CaseIterable, Identifiable, Sendable {
    case never = -1
    case day = 1
    case threeDays = 3
    case week = 7
    case twoWeeks = 14
    case month = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: return String(localized: "Never")
        case .day: return String(localized: "After 1 Day")
        case .threeDays: return String(localized: "After 3 Days")
        case .week: return String(localized: "After 1 Week")
        case .twoWeeks: return String(localized: "After 2 Weeks")
        case .month: return String(localized: "After 1 Month")
        }
    }

    /// The instant before which a capture is old enough to go, or `nil` when nothing expires.
    func cutoff(from now: Date) -> Date? {
        self == .never ? nil : now.addingTimeInterval(-TimeInterval(rawValue) * 86_400)
    }
}
