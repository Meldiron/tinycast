import SwiftUI

/// Day sections of thumbnails, two to a row. See docs/features/screenshots.md#the-screen.
struct ScreenshotGridView: View {
    static let columns = 2

    @Environment(\.metrics) private var metrics
    let sections: [ScreenshotSection]
    /// Flat selection index across all sections, as in the list modes.
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    let drag: (ScreenCapture) -> RowDrag

    private var items: [ScreenshotGridItem] {
        var items: [ScreenshotGridItem] = []
        for section in sections {
            items.append(.header(section))
            var offset = 0
            while offset < section.captures.count {
                let end = min(offset + Self.columns, section.captures.count)
                items.append(
                    .row(
                        ScreenshotGridRow(
                            id: Self.rowID(section, row: offset / Self.columns),
                            start: section.start + offset,
                            captures: Array(section.captures[offset..<end]))))
                offset = end
            }
        }
        return items
    }

    /// Section-namespaced, so a day's first row keeps its identity as newer days arrive above it.
    private static func rowID(_ section: ScreenshotSection, row: Int) -> String {
        "\(section.day.timeIntervalSinceReferenceDate)-\(row)"
    }

    private var selectedRowID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.captures.count
        else { return nil }
        return Self.rowID(section, row: (selection - section.start) / Self.columns)
    }

    private var firstRowID: String? { sections.first.map { Self.rowID($0, row: 0) } }

    var body: some View {
        let items = items
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(let section):
                            ScreenshotSectionHeader(section: section, isFirst: item.id == items.first?.id)
                        case .row(let row):
                            ScreenshotGridRowView(
                                row: row, selection: selection, onSelect: onSelect,
                                onActivate: onActivate, onActions: onActions, drag: drag
                            )
                            .padding(.bottom, metrics.spacing.md)
                            .selectionFrame(row.id == selectedRowID)
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selectedRowID == firstRowID, proxy: proxy)
        }
    }
}

private struct ScreenshotGridRow: Identifiable {
    let id: String
    let start: Int
    let captures: [ScreenCapture]
}

private enum ScreenshotGridItem: Identifiable {
    case header(ScreenshotSection)
    case row(ScreenshotGridRow)

    var id: String {
        switch self {
        case .header(let section): return "header-\(section.day.timeIntervalSinceReferenceDate)"
        case .row(let row): return row.id
        }
    }
}

/// The count and the space a day takes, which is what deciding to clear it needs.
private struct ScreenshotSectionHeader: View {
    @Environment(\.metrics) private var metrics
    let section: ScreenshotSection
    let isFirst: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(section.title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(section.captures.count, format: .number)
                .foregroundStyle(Theme.Colors.textTertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(section.byteCount, format: .byteCount(style: .file))
                .foregroundStyle(Theme.Colors.textTertiary)
                .monospacedDigit()
        }
        .font(metrics.typography.sectionHeader)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.lg)
        .padding(.bottom, metrics.spacing.md)
        .accessibilityElement(children: .combine)
    }
}

private struct ScreenshotGridRowView: View {
    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let row: ScreenshotGridRow
    let selection: Int
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    let drag: (ScreenCapture) -> RowDrag
    @State private var hovered: Int?

    private var cellWidth: CGFloat {
        let spacing = metrics.spacing.md * CGFloat(ScreenshotGridView.columns - 1)
        let content = metrics.size.screenshotGridWidth - metrics.spacing.lg * 2 - spacing
        return content / CGFloat(ScreenshotGridView.columns)
    }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.md) {
            ForEach(Array(row.captures.enumerated()), id: \.element.id) { offset, capture in
                let flat = row.start + offset
                ScreenshotCell(
                    capture: capture, selected: flat == selection, hovered: hovered == flat,
                    width: cellWidth
                )
                .onRowClick(
                    select: { onSelect(flat) }, activate: { onActivate(flat) }, drag: drag(capture)
                )
                .onRightClick { onActions(flat) }
                .onHover { inside in
                    if inside, palette.hoverHighlightArmed {
                        hovered = flat
                    } else if hovered == flat {
                        hovered = nil
                    }
                }
            }
        }
        .onChange(of: palette.hoverDisarmToken) { hovered = nil }
    }
}

/// Pure content: interaction belongs to the row, as in the emoji grid.
private struct ScreenshotCell: View {
    @Environment(\.metrics) private var metrics
    let capture: ScreenCapture
    let selected: Bool
    let hovered: Bool
    let width: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            ScreenshotThumbnail(capture: capture, maxPixel: metrics.size.screenshotThumbnailPixel)
                .frame(width: width, height: width / Theme.Size.screenshotThumbnailAspect)
                .clipShape(shape)
                .overlay(alignment: .topTrailing) { badges }
                .overlay { border }
            Text(capture.capturedAt, format: .dateTime.hour().minute())
                .font(metrics.typography.keyCap)
                .foregroundStyle(selected ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .monospacedDigit()
                .padding(.leading, metrics.spacing.xs)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capture.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var border: some View {
        if selected {
            shape.strokeBorder(Theme.Colors.screenshotSelectionBorder, lineWidth: 2)
        } else if hovered {
            shape.strokeBorder(Theme.Colors.screenshotHoverBorder, lineWidth: 2)
        } else {
            shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline)
        }
    }

    private var badges: some View {
        HStack(spacing: metrics.spacing.xs) {
            if capture.kind == .recording { badge("video.fill") }
            if capture.isKept { badge("pin.fill") }
        }
        .padding(metrics.spacing.sm)
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(metrics.typography.keyCap)
            .foregroundStyle(.white)
            .padding(metrics.spacing.xs)
            .background(.black.opacity(0.55), in: Circle())
    }
}

/// ImageIO for a screenshot, QuickLook for a recording's poster frame; misses decode off-main.
struct ScreenshotThumbnail: View {
    let capture: ScreenCapture
    let maxPixel: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.Colors.emojiCell
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: capture) {
            if let hit = cached {
                image = hit
                return
            }
            image = nil
            image = await load()
        }
    }

    private var cached: NSImage? {
        switch capture.kind {
        case .screenshot: return ImageThumbnail.cached(capture.url, maxPixel: maxPixel)
        case .recording: return FilePreviewThumbnail.cached(capture.url, maxPixel: maxPixel)
        }
    }

    private func load() async -> NSImage? {
        switch capture.kind {
        case .screenshot: return await ImageThumbnail.loadAsync(capture.url, maxPixel: maxPixel)
        case .recording: return await FilePreviewThumbnail.loadAsync(capture.url, maxPixel: maxPixel)
        }
    }
}
