import Foundation

/// Text Vision read out of each screenshot, so a search finds a capture by what it shows.
@MainActor
@Observable
final class ScreenshotTextStore {
    /// A changed size or date means a different file under the same name, so its text is stale.
    private struct Record: Codable, Sendable {
        let byteCount: Int64
        let capturedAt: Date
        let text: String
    }

    /// Bounds one pass, so a folder of years of captures is read a screenful at a time.
    private static let passLimit = 200

    /// Bumped as text lands, so an open search re-filters without observing every record.
    private(set) var revision = 0
    private(set) var isRecognizing = false

    @ObservationIgnored private var records: [String: Record]
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL

    init(
        fileURL: URL = AppPaths.applicationSupport().appendingPathComponent("screenshot-text.json")
    ) {
        self.fileURL = fileURL
        records =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    func text(for capture: ScreenCapture) -> String? {
        guard let record = records[capture.id], record.byteCount == capture.byteCount,
            record.capturedAt == capture.capturedAt
        else { return nil }
        return record.text
    }

    /// Newest first and one helper at a time, so the Mac never notices it running.
    func recognize(_ captures: [ScreenCapture]) {
        guard pass == nil else { return }
        let pending = Array(
            captures.lazy.filter { $0.kind == .screenshot && self.text(for: $0) == nil }
                .prefix(Self.passLimit))
        guard !pending.isEmpty else { return }
        isRecognizing = true
        pass = Task { [weak self] in
            for capture in pending {
                let text = await Self.read(capture.url)
                guard !Task.isCancelled, let self else { break }
                self.records[capture.id] = Record(
                    byteCount: capture.byteCount, capturedAt: capture.capturedAt, text: text)
                self.revision &+= 1
            }
            self?.finishPass(keeping: captures)
        }
    }

    func cancel() {
        pass?.cancel()
    }

    /// Turning the setting off takes the text with it, file and all.
    func clear() {
        pass?.cancel()
        records = [:]
        revision &+= 1
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func finishPass(keeping captures: [ScreenCapture]) {
        pass = nil
        isRecognizing = false
        let present = Set(captures.map(\.id))
        records = records.filter { present.contains($0.key) }
        // A pass that `clear` cancelled lands here too, and must not write the text back.
        guard !records.isEmpty, let data = try? JSONEncoder().encode(records) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// An unreadable capture stores no text rather than failing again on every open.
    private static func read(_ url: URL) async -> String {
        let text = try? await ClipboardTextWorker.extract(
            at: url, isPDF: false, executable: ClipboardTextWorker.executable)
        return text ?? ""
    }
}
