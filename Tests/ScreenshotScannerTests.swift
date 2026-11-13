import Darwin
import Foundation

@main
@MainActor
struct ScreenshotScannerTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static let folder = FileManager.default.temporaryDirectory
        .appending(path: "tinycast-screenshot-scanner-\(UUID().uuidString)", directoryHint: .isDirectory)

    @discardableResult
    static func file(_ name: String, in directory: URL = folder, tag: String? = nil) -> URL {
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        FileManager.default.createFile(atPath: url.path, contents: Data("capture".utf8))
        if let tag {
            let value: [UInt8] = [1]
            setxattr(url.path, tag, value, value.count, 0, XATTR_NOFOLLOW)
        }
        return url
    }

    static func main() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let screenshotTag = "com.apple.metadata:kMDItemIsScreenCapture"
        let typeTag = "com.apple.metadata:kMDItemScreenCaptureType"

        let shot = file("Screenshot 1.png", tag: screenshotTag)
        file("Screen Recording 1.mov", tag: typeTag)
        file("Holiday.png")
        file(".Screenshot hidden.png", tag: screenshotTag)
        let nested = folder.appending(path: "Nested", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        file("Screenshot nested.png", in: nested, tag: screenshotTag)

        let captures = (try? ScreenshotScanner.scan(folder)) ?? []
        expect(
            Set(captures.map(\.name)) == ["Screenshot 1.png", "Screen Recording 1.mov"],
            "only tagged, visible, top-level files are captures: \(captures.map(\.name))")
        expect(
            captures.first { $0.name.hasSuffix(".mov") }?.kind == .recording,
            "a movie is a recording")
        expect(captures.first { $0.name.hasSuffix(".png") }?.kind == .screenshot, "a PNG is a screenshot")
        expect(captures.allSatisfy { $0.byteCount == 7 }, "sizes come from the file")
        expect(captures.allSatisfy { !$0.isKept }, "nothing starts kept")
        expect(
            zip(captures, captures.dropFirst()).allSatisfy { $0.capturedAt >= $1.capturedAt },
            "newest first")

        expect(ScreenshotScanner.setKept(true, at: shot), "keeping writes the marker")
        expect(ScreenshotScanner.capture(at: shot)?.isKept == true, "the marker reads back")
        expect(ScreenshotScanner.setKept(false, at: shot), "un-keeping removes it")
        expect(ScreenshotScanner.capture(at: shot)?.isKept == false, "and it reads back cleared")
        expect(ScreenshotScanner.setKept(false, at: shot), "removing an absent marker still succeeds")

        let missing = folder.appending(path: "Gone", directoryHint: .isDirectory)
        do {
            _ = try ScreenshotScanner.scan(missing)
            expect(false, "a missing folder throws")
        } catch {
            expect(error == .unreadable, "a missing folder is unreadable, not a permission problem")
        }

        let locked = folder.appending(path: "Locked", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        chmod(locked.path, 0o000)
        defer { chmod(locked.path, 0o755) }
        do {
            _ = try ScreenshotScanner.scan(locked)
            expect(false, "a locked folder throws")
        } catch {
            expect(error == .noAccess, "a refused read asks for access")
        }

        let home = URL(filePath: "/Users/nobody", directoryHint: .isDirectory)
        expect(ScreenshotScanner.folder(home: home).hasDirectoryPath, "the folder is a directory URL")

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("ScreenshotScannerTests passed")
    }
}
