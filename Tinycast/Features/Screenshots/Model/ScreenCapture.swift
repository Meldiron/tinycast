import Foundation

/// One file macOS saved for a screenshot or a screen recording.
struct ScreenCapture: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case screenshot
        case recording
    }

    let url: URL
    let kind: Kind
    let capturedAt: Date
    let byteCount: Int64
    /// Stored on the file itself, so a rename or a move inside the folder keeps it.
    var isKept: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}
