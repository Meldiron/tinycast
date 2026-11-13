import Foundation

/// The header filter, answered before the query so a search never reaches past it.
enum ScreenshotFilter: CaseIterable, Sendable {
    case all
    case screenshots
    case recordings
    case kept

    var title: String {
        switch self {
        case .all: return String(localized: "All Captures")
        case .screenshots: return String(localized: "Screenshots")
        case .recordings: return String(localized: "Screen Recordings")
        case .kept: return String(localized: "Kept")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .screenshots: return "photo"
        case .recordings: return "video"
        case .kept: return "pin"
        }
    }

    func admits(_ capture: ScreenCapture) -> Bool {
        switch self {
        case .all: return true
        case .screenshots: return capture.kind == .screenshot
        case .recordings: return capture.kind == .recording
        case .kept: return capture.isKept
        }
    }
}
