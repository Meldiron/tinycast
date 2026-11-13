import AppKit
import UniformTypeIdentifiers

/// A capture on the board as the clipboard history writes an image: its pixels and its file.
@MainActor
enum ScreenshotPasteboard {
    private static var stagingFolder: URL {
        AppPaths.caches().appending(path: "Screenshots", directoryHint: .isDirectory)
    }

    /// A staged copy outlives this, so a receiver that reads the file late still finds it.
    private static let stagedLifetime: TimeInterval = 24 * 3_600

    /// Marked as Tinycast's own, as every paste Tinycast makes is, so history does not record it.
    @discardableResult
    static func write(_ capture: ScreenCapture, file: URL, to pasteboard: NSPasteboard = .general)
        -> Bool
    {
        let image = capture.kind == .screenshot ? imageData(at: file) : nil
        if capture.kind == .screenshot, image == nil { return false }
        pasteboard.clearContents()
        guard let image else {
            pasteboard.declareTypes([.fileURL, .string, ClipboardManager.internalType], owner: nil)
            pasteboard.setData(file.dataRepresentation, forType: .fileURL)
            pasteboard.setString(file.path, forType: .string)
            pasteboard.setData(Data(), forType: ClipboardManager.internalType)
            return true
        }
        pasteboard.declareTypes([image.type, .fileURL, ClipboardManager.internalType], owner: nil)
        pasteboard.setData(image.data, forType: image.type)
        // A text-only receiver ignores the pixels but pastes a file URL as its path.
        pasteboard.setData(file.dataRepresentation, forType: .fileURL)
        pasteboard.setData(Data(), forType: ClipboardManager.internalType)
        return true
    }

    /// A clone beside Tinycast's caches, which the original can then leave for the Trash behind.
    static func stage(_ url: URL) throws -> URL {
        let folder = stagingFolder
        pruneStaged(in: folder)
        let destination = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let copy = destination.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    /// PNG as it was saved; any other format goes over as TIFF, which every image field reads.
    private static func imageData(at url: URL) -> (data: Data, type: NSPasteboard.PasteboardType)? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        if type?.conforms(to: .png) == true,
            let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        {
            return (data, .png)
        }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation else { return nil }
        return (tiff, .tiff)
    }

    private static func pruneStaged(in folder: URL) {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-stagedLifetime)
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let created, created < cutoff { try? FileManager.default.removeItem(at: entry) }
        }
    }
}
