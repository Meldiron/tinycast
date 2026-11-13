import AppKit
import OSLog

/// The Screenshots screen's action surface, and the clean-up that runs whether it is open or not.
@MainActor
final class ScreenshotsCoordinator {
    private static let logger = Logger(subsystem: "com.tinycast", category: "Screenshots")
    private static let cleanupInterval = Duration.seconds(60 * 60)

    private let settings: AppSettings
    private let index: ScreenshotIndex
    private let text: ScreenshotTextStore
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let windowController: PaletteWindowController
    private unowned let core: AppCore
    private var sharePicker: NSSharingServicePicker?
    private var cleanup: Task<Void, Never>?
    private var isBrowsing = false

    init(
        settings: AppSettings, index: ScreenshotIndex, text: ScreenshotTextStore,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        windowController: PaletteWindowController, core: AppCore
    ) {
        self.settings = settings
        self.index = index
        self.text = text
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.windowController = windowController
        self.core = core
    }

    // MARK: - The screen

    func show(query: String = "") {
        paletteCoordinator.togglePalette(mode: .screenshots, seeding: query.isEmpty ? nil : query)
    }

    /// Live only while it is looked at: the folder is watched and its text read for that long.
    func setBrowsing(_ browsing: Bool) {
        guard browsing != isBrowsing else { return }
        isBrowsing = browsing
        if browsing {
            index.refresh()
            index.startWatching()
            // A rescan that finds the same captures changes nothing, so it would never start one.
            capturesChanged()
        } else {
            index.stopWatching()
            text.cancel()
        }
    }

    func capturesChanged() {
        guard isBrowsing, settings.screenshotTextSearchEnabled else { return }
        text.recognize(index.captures)
    }

    func applyTextSearch() {
        if settings.screenshotTextSearchEnabled {
            capturesChanged()
        } else {
            text.clear()
        }
    }

    func openAccessSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Permissions.openFilesAndFoldersSettings()
    }

    func showSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.settingsCoordinator.showSettings(tab: .screenshots)
    }

    func showFolder() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(index.folder)
    }

    // MARK: - Pasting and copying

    /// `afterUse` overrides the setting for one paste: ⌃⌘↵ is always the other choice.
    func paste(_ capture: ScreenCapture, afterUse: ScreenshotAfterUse? = nil) {
        let afterUse = afterUse ?? settings.screenshotAfterUse
        let target = windowController.previousApp
        guard writeBoard(capture, afterUse: afterUse) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteBoard(into: target)
        finishUse(of: capture, afterUse: afterUse)
    }

    /// ⌥↵: the palette stays up, so several captures go over in one visit.
    func pasteKeepingWindowOpen(_ capture: ScreenCapture) {
        let afterUse = settings.screenshotAfterUse
        guard writeBoard(capture, afterUse: afterUse) else { return }
        Paster.pasteBoardInPlace(into: windowController.previousApp)
        finishUse(of: capture, afterUse: afterUse)
    }

    func copy(_ capture: ScreenCapture) {
        let afterUse = settings.screenshotAfterUse
        guard writeBoard(capture, afterUse: afterUse) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        finishUse(of: capture, afterUse: afterUse)
        core.showMessage(
            afterUse == .moveToTrash
                ? String(localized: "Copied, and moved the file to the Trash")
                : String(localized: "Copied to the clipboard"))
    }

    /// The newest screenshot into the app in front, read fresh so one taken a second ago counts.
    func pasteLatest() {
        let target = paletteCoordinator.targetApp
        Task {
            let scan = await index.scanNow()
            guard case .success(let captures) = scan else {
                await reportUnreadableFolder(scan)
                return
            }
            guard let latest = captures.first(where: { $0.kind == .screenshot }) else {
                core.showMessage(String(localized: "No screenshots yet"), tone: .neutral)
                return
            }
            let afterUse = settings.screenshotAfterUse
            guard writeBoard(latest, afterUse: afterUse) else { return }
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            Paster.pasteBoard(into: target)
            finishUse(of: latest, afterUse: afterUse)
        }
    }

    func copyText(_ capture: ScreenCapture) {
        guard let recognized = recognizedText(of: capture) else { return }
        Paster.copyPlainText(recognized)
        core.showMessage(String(localized: "Copied text"))
    }

    func recognizedText(of capture: ScreenCapture) -> String? {
        guard settings.screenshotTextSearchEnabled, let recognized = text.text(for: capture) else {
            return nil
        }
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A file about to leave goes over as a staged clone, so the board never names the Trash.
    private func writeBoard(_ capture: ScreenCapture, afterUse: ScreenshotAfterUse) -> Bool {
        do {
            let file = afterUse == .moveToTrash ? try ScreenshotPasteboard.stage(capture.url) : capture.url
            if ScreenshotPasteboard.write(capture, file: file) { return true }
        } catch {
            Self.logger.error("Staging \(capture.name, privacy: .private) failed: \(error)")
        }
        index.refresh()
        Task {
            await core.showNotice(
                title: String(localized: "Couldn’t Read \(capture.name)"),
                message: String(localized: "It may have been moved, renamed or deleted."),
                symbol: "photo", tone: .danger)
        }
        return false
    }

    private func finishUse(of capture: ScreenCapture, afterUse: ScreenshotAfterUse) {
        guard afterUse == .moveToTrash else { return }
        Task { await moveToTrash([capture]) }
    }

    // MARK: - Files

    func open(_ capture: ScreenCapture) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    capture.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: String(localized: "Couldn’t Open \(capture.name)"),
                    message: error.localizedDescription, symbol: "photo", tone: .danger)
            }
        }
    }

    func showInFinder(_ capture: ScreenCapture) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(capture.url)
    }

    /// macOS's own share sheet, anchored to the palette's trailing edge so the grid stays beside it.
    func share(_ capture: ScreenCapture) {
        guard let provider = NSItemProvider(contentsOf: capture.url),
            let anchor = paletteCoordinator.anchorView
        else { return }
        let picker = NSSharingServicePicker(items: [provider])
        sharePicker = picker
        picker.show(
            relativeTo: CGRect(x: anchor.bounds.maxX, y: anchor.bounds.midY, width: 0, height: 0),
            of: anchor, preferredEdge: .maxX)
    }

    func copyFile(_ capture: ScreenCapture) {
        PasteboardFiles.write(capture.url, to: .general)
        core.showMessage(String(localized: "Copied file"))
    }

    func copyPath(_ capture: ScreenCapture) {
        Paster.copyPlainText(capture.url.path)
        core.showMessage(String(localized: "Copied path"))
    }

    func toggleKept(_ capture: ScreenCapture) {
        var updated = capture
        updated.isKept.toggle()
        guard ScreenshotScanner.setKept(updated.isKept, at: capture.url) else {
            core.showMessage(String(localized: "Couldn’t change \(capture.name)"), tone: .danger)
            return
        }
        index.replace(updated)
        core.showMessage(
            updated.isKept
                ? String(localized: "Kept: clean-up will leave it alone")
                : String(localized: "No longer kept"))
    }

    // MARK: - The Trash

    /// One capture asks nothing first: the Trash puts it back, as File Search's delete relies on.
    func trash(_ capture: ScreenCapture) {
        Task {
            guard await moveToTrash([capture]) > 0 else { return }
            core.showMessage(String(localized: "Moved to Trash"))
        }
    }

    /// Several at once confirm with the count and the space, and never take a kept capture.
    func trash(_ captures: [ScreenCapture]) {
        let removable = ScreenshotCleanupPolicy.removable(captures)
        guard !removable.isEmpty else {
            core.showMessage(String(localized: "Nothing to move: every one is kept"), tone: .neutral)
            return
        }
        let size = ScreenshotCleanupPolicy.byteCount(of: removable).formatted(.byteCount(style: .file))
        let keptCount = captures.count - removable.count
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Move \(removable.count) items to the Trash?"),
                    message: keptCount > 0
                        ? String(localized: "This frees \(size). \(keptCount) kept items stay put.")
                        : String(localized: "This frees \(size). You can put them back from the Trash."),
                    symbol: "trash", confirmTitle: String(localized: "Move to Trash"))
            else { return }
            let moved = await moveToTrash(removable)
            core.showMessage(String(localized: "Moved \(moved) items to the Trash"))
        }
    }

    /// Returns how many left; a file already gone counts as gone, which is what was asked.
    @discardableResult
    private func moveToTrash(_ captures: [ScreenCapture]) async -> Int {
        let urls = captures.map(\.url)
        let moved = await Task.detached(priority: .userInitiated) {
            urls.filter { url in
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    return true
                } catch {
                    return !FileManager.default.fileExists(atPath: url.path)
                }
            }
        }.value
        index.remove(Set(moved.map(\.path)))
        if moved.count < urls.count {
            core.showMessage(
                String(localized: "\(urls.count - moved.count) items couldn’t be moved"), tone: .danger)
        }
        return moved.count
    }

    // MARK: - Automatic clean-up

    /// Hourly while a retention is set; the first sweep runs right away so a new choice applies.
    func applyAutoDelete() {
        cleanup?.cancel()
        cleanup = nil
        guard settings.screenshotAutoDelete != .never else { return }
        cleanup = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sweep()
                try? await Task.sleep(for: Self.cleanupInterval)
            }
        }
    }

    private func sweep() async {
        guard case .success(let captures) = await index.scanNow() else { return }
        let expired = ScreenshotCleanupPolicy.expired(
            captures, after: settings.screenshotAutoDelete, now: Date())
        guard !expired.isEmpty, !Task.isCancelled else { return }
        let moved = await moveToTrash(expired)
        Self.logger.info("Clean-up moved \(moved) captures to the Trash")
    }

    private func reportUnreadableFolder(_ scan: ScreenshotIndex.Scan) async {
        guard case .failure(let failure) = scan else { return }
        let folder = index.folder.lastPathComponent
        switch failure {
        case .noAccess:
            guard
                await core.confirm(
                    title: String(localized: "Tinycast can’t read \(folder)"),
                    message: String(
                        localized: "Allow it under Files & Folders, then try again."),
                    symbol: "lock.shield", confirmTitle: String(localized: "Open Privacy Settings"),
                    tone: .neutral, confirmRole: .standard)
            else { return }
            Permissions.openFilesAndFoldersSettings()
        case .unreadable:
            await core.showNotice(
                title: String(localized: "Couldn’t Read \(folder)"),
                message: String(localized: "Check that the screenshot folder still exists."),
                symbol: "folder", tone: .danger)
        }
    }
}
