import CoreServices
import Foundation

/// The screenshot folder's captures, read off the main actor and kept live while watched.
@MainActor
@Observable
final class ScreenshotIndex {
    enum Status: Equatable {
        case idle
        case ready
        case needsAccess
        case failed
    }

    typealias Scan = Result<[ScreenCapture], ScreenshotScanner.Failure>

    private(set) var captures: [ScreenCapture] = []
    private(set) var status: Status = .idle
    private(set) var folder: URL

    @ObservationIgnored private let home: URL
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FileSystemWatcher?
    @ObservationIgnored private let events = DispatchQueue(
        label: "com.tinycast.screenshots.events", qos: .utility)

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        folder = ScreenshotScanner.folder(home: home)
    }

    /// Re-reads Save to as well, so a folder changed in ⇧⌘5 shows on the next open.
    func refresh() {
        let folder = ScreenshotScanner.folder(home: home)
        if folder != self.folder {
            self.folder = folder
            if watcher != nil { watch(folder) }
        }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let scan = await Self.scan(folder)
            guard !Task.isCancelled, let self, self.folder == folder else { return }
            self.apply(scan)
        }
    }

    /// A read of its own for one-shot work, so a paste or a clean-up never waits on the screen.
    func scanNow() async -> Scan {
        let scan = await Self.scan(ScreenshotScanner.folder(home: home))
        if case .success = scan, scanTask == nil { apply(scan) }
        return scan
    }

    func startWatching() {
        guard watcher == nil else { return }
        watch(folder)
    }

    func stopWatching() {
        watcher = nil
        scanTask?.cancel()
        scanTask = nil
    }

    func remove(_ ids: Set<String>) {
        captures.removeAll { ids.contains($0.id) }
    }

    func replace(_ capture: ScreenCapture) {
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return }
        captures[index] = capture
    }

    private func watch(_ folder: URL) {
        let changed: @Sendable ([FileSystemWatcher.Event]) -> Void = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        watcher = FileSystemWatcher(
            paths: [folder.path], since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            queue: events, handler: changed)
    }

    private func apply(_ scan: Scan) {
        scanTask = nil
        switch scan {
        case .success(let captures):
            if captures != self.captures { self.captures = captures }
            status = .ready
        case .failure(.noAccess):
            captures = []
            status = .needsAccess
        case .failure(.unreadable):
            captures = []
            status = .failed
        }
    }

    @concurrent
    private static func scan(_ folder: URL) async -> Scan {
        Scan { () throws(ScreenshotScanner.Failure) in try ScreenshotScanner.scan(folder) }
    }
}
