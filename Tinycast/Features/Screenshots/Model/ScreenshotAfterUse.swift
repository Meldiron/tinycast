import Foundation

/// What becomes of the file once it has been pasted or copied; the board keeps its own copy.
enum ScreenshotAfterUse: String, CaseIterable, Identifiable, Sendable {
    case keep
    case moveToTrash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return String(localized: "Keep the File")
        case .moveToTrash: return String(localized: "Move It to the Trash")
        }
    }

    /// The ⌃⌘↵ variant: whichever the setting leaves out, so both stay one chord away.
    var opposite: Self {
        switch self {
        case .keep: return .moveToTrash
        case .moveToTrash: return .keep
        }
    }
}
