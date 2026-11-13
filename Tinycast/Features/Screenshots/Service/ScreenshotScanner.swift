import Darwin
import Foundation
import UniformTypeIdentifiers

/// Lists what macOS itself saved: a file in the folder without its capture tag is the user's own.
nonisolated enum ScreenshotScanner {
    enum Failure: Error {
        case noAccess
        case unreadable
    }

    /// Written by `screencapture` on every capture, including recordings made from ⇧⌘5.
    private static let captureAttributes = [
        "com.apple.metadata:kMDItemIsScreenCapture", "com.apple.metadata:kMDItemScreenCaptureType"
    ]
    private static let keptAttribute = "com.tinycast.screenshot.kept"
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .creationDateKey, .fileSizeKey, .contentTypeKey
    ]

    /// Screenshot ▸ Options ▸ Save to, else the Desktop macOS falls back to.
    static func folder(home: URL) -> URL {
        let value = CFPreferencesCopyAppValue(
            "location" as CFString, "com.apple.screencapture" as CFString)
        guard let location = value as? String, !location.isEmpty else {
            return home.appending(path: "Desktop", directoryHint: .isDirectory)
        }
        return URL(
            filePath: (location as NSString).expandingTildeInPath, directoryHint: .isDirectory
        ).standardizedFileURL
    }

    /// Newest first, which is the order every section and the latest-capture command assume.
    static func scan(_ folder: URL) throws(Failure) -> [ScreenCapture] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants])
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw .noAccess
        } catch {
            throw .unreadable
        }
        return urls.compactMap(capture(at:)).sorted {
            $0.capturedAt == $1.capturedAt ? $0.name > $1.name : $0.capturedAt > $1.capturedAt
        }
    }

    static func capture(at url: URL) -> ScreenCapture? {
        guard captureAttributes.contains(where: { hasAttribute($0, at: url) }),
            let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true
        else { return nil }
        let isMovie = values.contentType?.conforms(to: .movie) ?? false
        return ScreenCapture(
            url: url, kind: isMovie ? .recording : .screenshot,
            capturedAt: values.creationDate ?? .distantPast,
            byteCount: Int64(values.fileSize ?? 0), isKept: hasAttribute(keptAttribute, at: url))
    }

    static func setKept(_ kept: Bool, at url: URL) -> Bool {
        if kept {
            let marker: [UInt8] = [1]
            return setxattr(url.path, keptAttribute, marker, marker.count, 0, XATTR_NOFOLLOW) == 0
        }
        return removexattr(url.path, keptAttribute, XATTR_NOFOLLOW) == 0 || errno == ENOATTR
    }

    private static func hasAttribute(_ name: String, at url: URL) -> Bool {
        getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}
