import ImageIO
import SwiftUI

/// The selected capture at reading size, then what it is and the text it shows.
struct ScreenshotPreview: View {
    @Environment(\.metrics) private var metrics
    let capture: ScreenCapture?
    let recognizedText: String?

    var body: some View {
        if let capture {
            VStack(alignment: .leading, spacing: 0) {
                ScreenshotPreviewStage(capture: capture)
                    .aspectRatio(Theme.Size.previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ScreenshotInfoSection(capture: capture)
                        if let recognizedText {
                            ScreenshotTextSection(text: recognizedText)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.xl)
        } else {
            Color.clear
        }
    }
}

/// File Search's surface, so a recording plays where a screenshot shows.
private struct ScreenshotPreviewStage: View {
    @Environment(\.metrics) private var metrics
    @Environment(PaletteState.self) private var palette
    let capture: ScreenCapture

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    var body: some View {
        Group {
            // Unmounting is the teardown: an ordered-out panel keeps its tree and its player.
            if palette.isVisible {
                FileSearchSurface(url: capture.url)
                    .clipShape(card)
                    .overlay(card.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, metrics.spacing.xl)
    }
}

private struct ScreenshotInfoSection: View {
    @Environment(\.metrics) private var metrics
    let capture: ScreenCapture
    @State private var pixels: CGSize?

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
        .task(id: capture.id) { await loadPixels() }
    }

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: String(localized: "Name"), value: capture.name),
            InfoRow(
                label: String(localized: "Captured"),
                value: capture.capturedAt.formatted(date: .abbreviated, time: .shortened)),
            InfoRow(
                label: String(localized: "Size"),
                value: capture.byteCount.formatted(.byteCount(style: .file)))
        ]
        if let pixels {
            rows.append(
                InfoRow(
                    label: String(localized: "Dimensions"),
                    value: String(localized: "\(Int(pixels.width)) × \(Int(pixels.height)) pixels")))
        }
        if capture.isKept {
            rows.append(
                InfoRow(
                    label: String(localized: "Clean-Up"),
                    value: String(localized: "Kept: never moved in bulk")))
        }
        return rows
    }

    private func loadPixels() async {
        pixels = nil
        guard capture.kind == .screenshot else { return }
        let url = capture.url
        let size = await Task.detached(priority: .userInitiated) { Self.pixelSize(of: url) }.value
        guard !Task.isCancelled else { return }
        pixels = size
    }

    /// The header alone: ImageIO answers without decoding a single pixel.
    private nonisolated static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// What Vision read, selectable, so a line can be lifted without copying the whole capture.
private struct ScreenshotTextSection: View {
    @Environment(\.metrics) private var metrics
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Text in Screenshot")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            Text(verbatim: text)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(12)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, metrics.spacing.md)
    }
}
