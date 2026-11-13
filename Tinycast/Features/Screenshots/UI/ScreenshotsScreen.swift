import SwiftUI

/// The screenshot folder as a grid of days; ↑/↓ move by visual row, as in the emoji grid.
struct ScreenshotsScreen: PaletteScreen {
    let index: ScreenshotIndex
    let text: ScreenshotTextStore
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    private var coordinator: ScreenshotsCoordinator { core.screenshotsCoordinator }
    private var settings: AppSettings { core.settings }
    private var metrics: InterfaceMetrics { settings.interfaceSize.metrics }
    private var needsAccess: Bool { index.status == .needsAccess }

    var sections: [ScreenshotSection] {
        let now = Date()
        let calendar = Calendar.current
        // Read so text recognised mid-search re-filters; the records themselves are unobserved.
        _ = text.revision
        let matches = ScreenshotQuery.filter(index.captures, query: vm.query, by: vm.screenshotFilter) {
            describe($0, now: now, calendar: calendar)
        }
        return ScreenshotSection.sections(of: matches, now: now, calendar: calendar, locale: .current)
    }

    var rows: [ScreenCapture] { sections.flatMap(\.captures) }

    /// ↵ on the access hint opens the one pane that can fix it.
    var actsWithoutRows: Bool { needsAccess }

    var primaryActionTitle: String {
        if needsAccess { return String(localized: "Open Privacy Settings") }
        return pasteTitle(settings.screenshotAfterUse, target: vm.pasteTarget)
    }

    private func capture(at selection: Int) -> ScreenCapture? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasPrimaryAction(at selection: Int) -> Bool { needsAccess || capture(at: selection) != nil }

    func hasActions(at selection: Int) -> Bool { capture(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let capture = capture(at: selection) else { return nil }
        let sections = sections
        return ScreenshotActionsMenu.content(
            capture: capture, section: sections.last { selection >= $0.start },
            shown: sections.flatMap(\.captures), all: index.captures,
            isNarrowed: !ScreenshotQuery.terms(in: vm.query).isEmpty || vm.screenshotFilter != .all,
            hasText: coordinator.recognizedText(of: capture) != nil,
            pasteTitle: pasteTitle(settings.screenshotAfterUse, target: vm.pasteTarget),
            alternatePasteTitle: pasteTitle(settings.screenshotAfterUse.opposite, target: vm.pasteTarget),
            core: core)
    }

    func activate(at selection: Int) {
        if needsAccess {
            coordinator.openAccessSettings()
            return
        }
        guard let capture = capture(at: selection) else { return }
        coordinator.paste(capture)
    }

    func secondary(at selection: Int) -> Bool {
        guard let capture = capture(at: selection) else { return false }
        coordinator.copy(capture)
        return true
    }

    func tertiary(at selection: Int) -> Bool {
        guard let capture = capture(at: selection) else { return false }
        coordinator.paste(capture, afterUse: settings.screenshotAfterUse.opposite)
        return true
    }

    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let capture = capture(at: selection) else { return false }
        coordinator.pasteKeepingWindowOpen(capture)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .settings {
            coordinator.showSettings()
            return true
        }
        guard let capture = capture(at: selection) else { return false }
        switch shortcut {
        case .copyFile: coordinator.copyFile(capture)
        case .copyPath: coordinator.copyPath(capture)
        case .copyText:
            guard coordinator.recognizedText(of: capture) != nil else { return false }
            coordinator.copyText(capture)
        case .openInApp: coordinator.open(capture)
        case .showInFinder: coordinator.showInFinder(capture)
        case .pin: coordinator.toggleKept(capture)
        // One capture goes without asking, as File Search's does: the Trash puts it back.
        case .delete: coordinator.trash(capture)
        case .deleteAll: coordinator.trash(rows)
        default: return false
        }
        return true
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let sections = sections
        let count = sections.reduce(0) { $0 + $1.captures.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: sections.map(\.captures.count), columns: ScreenshotGridView.columns)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), count - 1)
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .modifier(ScreenshotBrowsing(index: index, coordinator: coordinator)))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let sections = sections
        if sections.isEmpty {
            emptyState
        } else {
            let selected = capture(at: selection)
            HStack(spacing: 0) {
                ScreenshotGridView(
                    sections: sections, selection: selection, scroll: scroll,
                    onSelect: { vm.selection = $0 },
                    onActivate: { activate(at: $0) },
                    onActions: { flat in
                        vm.selection = flat
                        openActions()
                    },
                    drag: drag
                )
                .frame(width: metrics.size.screenshotGridWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: Theme.Size.hairline)
                ScreenshotPreview(
                    capture: selected,
                    recognizedText: selected.flatMap(coordinator.recognizedText(of:)))
            }
        }
    }

    /// Copy only, as every row drag is, so the file stays in the folder it was saved to.
    private func drag(_ capture: ScreenCapture) -> RowDrag {
        RowDrag(
            item: {
                .file(
                    capture.url,
                    image: ImageThumbnail.cached(
                        capture.url, maxPixel: metrics.size.screenshotThumbnailPixel))
            },
            dropped: { core.paletteCoordinator.dragLanded() })
    }

    @ViewBuilder
    private var emptyState: some View {
        let folder = index.folder.lastPathComponent
        switch index.status {
        case .idle:
            Color.clear
        case .needsAccess:
            EmptyResults(
                text: String(localized: "Tinycast can’t read your screenshots"),
                detail: String(
                    localized: """
                        macOS keeps \(folder) private. Press ↵ to open Files & Folders, then allow \
                        Tinycast.
                        """),
                systemImage: "lock.shield")
        case .failed:
            EmptyResults(
                text: String(localized: "Couldn’t read the screenshot folder"),
                detail: index.folder.path, systemImage: "exclamationmark.triangle")
        case .ready where index.captures.isEmpty:
            EmptyResults(
                text: String(localized: "No screenshots yet"),
                detail: String(
                    localized: """
                        Press ⇧⌘4 to capture part of the screen, or ⇧⌘5 for every option. Captures \
                        show up here as soon as macOS saves them to \(folder).
                        """),
                systemImage: "camera.viewfinder")
        case .ready:
            EmptyResults(
                text: String(localized: "No captures match"),
                detail: settings.screenshotTextSearchEnabled
                    ? nil
                    : String(
                        localized: """
                            Turn on Search text in screenshots in Settings to find captures by \
                            what they show.
                            """))
        }
    }

    private func pasteTitle(_ afterUse: ScreenshotAfterUse, target: PasteTarget?) -> String {
        switch afterUse {
        case .keep: return target?.pasteTitle ?? String(localized: "Paste")
        case .moveToTrash: return String(localized: "Paste and Move to Trash")
        }
    }

    /// The words a capture answers to besides its name; only built while a query is typed.
    private func describe(_ capture: ScreenCapture, now: Date, calendar: Calendar) -> [String] {
        var words = [
            ScreenshotSection.title(
                for: calendar.startOfDay(for: capture.capturedAt), now: now, calendar: calendar,
                locale: .current),
            capture.kind == .recording
                ? String(localized: "Screen Recording") : String(localized: "Screenshot")
        ]
        if capture.isKept { words.append(String(localized: "Kept")) }
        if let recognized = coordinator.recognizedText(of: capture) { words.append(recognized) }
        return words
    }
}

/// Live while looked at: an ordered-out palette keeps this mounted, so visibility says when.
private struct ScreenshotBrowsing: ViewModifier {
    @Environment(PaletteState.self) private var palette
    let index: ScreenshotIndex
    let coordinator: ScreenshotsCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: palette.isVisible, initial: true) { _, visible in
                coordinator.setBrowsing(visible)
            }
            .onDisappear { coordinator.setBrowsing(false) }
            .onChange(of: index.captures) { coordinator.capturesChanged() }
    }
}

@MainActor
enum ScreenshotActionsMenu {
    static func content(
        capture: ScreenCapture, section: ScreenshotSection?, shown: [ScreenCapture],
        all: [ScreenCapture], isNarrowed: Bool, hasText: Bool, pasteTitle: String,
        alternatePasteTitle: String, core: AppCore
    ) -> PopoverMenuContent {
        let coordinator = core.screenshotsCoordinator
        var items = [
            PopoverMenuItem(title: pasteTitle, systemImage: "doc.on.clipboard", shortcut: "↵") {
                coordinator.paste(capture)
            },
            PopoverMenuItem(
                title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.doc",
                shortcut: "⌘↵"
            ) { coordinator.copy(capture) },
            PopoverMenuItem(title: alternatePasteTitle, systemImage: "arrow.uturn.down", shortcut: "⌃⌘↵") {
                coordinator.paste(capture, afterUse: core.settings.screenshotAfterUse.opposite)
            },
            PopoverMenuItem(
                title: String(localized: "Paste and Keep Window Open"), systemImage: "macwindow",
                shortcut: "⌥↵"
            ) { coordinator.pasteKeepingWindowOpen(capture) },
            PopoverMenuItem(
                title: String(localized: "Open"), systemImage: "arrow.up.forward.app",
                startsSection: true, shortcut: "⌘O"
            ) { coordinator.open(capture) },
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder", shortcut: "⌘F"
            ) { coordinator.showInFinder(capture) },
            PopoverMenuItem(title: String(localized: "Share…"), systemImage: "square.and.arrow.up") {
                coordinator.share(capture)
            },
            PopoverMenuItem(
                title: String(localized: "Copy File"), systemImage: "doc.on.clipboard",
                startsSection: true, shortcut: "⇧⌘C"
            ) { coordinator.copyFile(capture) },
            PopoverMenuItem(
                title: String(localized: "Copy Path"), systemImage: "doc.on.clipboard", shortcut: "⌃⌘C"
            ) { coordinator.copyPath(capture) }
        ]
        if hasText {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy Text in Screenshot"), systemImage: "text.viewfinder",
                    shortcut: "⇧⌘T"
                ) { coordinator.copyText(capture) })
        }
        items.append(
            PopoverMenuItem(
                title: capture.isKept ? String(localized: "Stop Keeping") : String(localized: "Keep"),
                systemImage: capture.isKept ? "pin.slash" : "pin", startsSection: true, shortcut: "⌘."
            ) { coordinator.toggleKept(capture) })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Move to Trash"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) { coordinator.trash(capture) })
        items += bulkItems(section: section, shown: shown, all: all, isNarrowed: isNarrowed, core: core)
        items.append(
            PopoverMenuItem(
                title: String(localized: "Show Screenshot Folder"), systemImage: "folder",
                startsSection: true
            ) { coordinator.showFolder() })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Screenshot Settings…"), systemImage: "gearshape",
                shortcut: "⌥⌘,"
            ) { coordinator.showSettings() })
        return PopoverMenuContent(header: capture.name, items: items)
    }

    /// Each offered only when it would take something a narrower row would not.
    private static func bulkItems(
        section: ScreenshotSection?, shown: [ScreenCapture], all: [ScreenCapture],
        isNarrowed: Bool, core: AppCore
    ) -> [PopoverMenuItem] {
        let coordinator = core.screenshotsCoordinator
        var items: [PopoverMenuItem] = []
        if let section, ScreenshotCleanupPolicy.removable(section.captures).count > 1 {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move All from \(section.title) to Trash"),
                    systemImage: "calendar.badge.minus", isDestructive: true
                ) { coordinator.trash(section.captures) })
        }
        if let section {
            let older = ScreenshotCleanupPolicy.before(section.day, in: all, calendar: .current)
            if !older.isEmpty {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Move Everything Before \(section.title) to Trash"),
                        systemImage: "clock.badge.xmark", isDestructive: true
                    ) { coordinator.trash(older) })
            }
        }
        if ScreenshotCleanupPolicy.removable(shown).count > 1 {
            items.append(
                PopoverMenuItem(
                    title: isNarrowed
                        ? String(localized: "Move All Results to Trash")
                        : String(localized: "Move All to Trash"),
                    systemImage: "trash.fill", shortcut: "⌃⇧X", isDestructive: true
                ) { coordinator.trash(shown) })
        }
        return items
    }
}
