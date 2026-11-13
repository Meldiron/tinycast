import Foundation

/// Every word must appear somewhere a person would describe the capture by, in any order.
enum ScreenshotQuery {
    static func terms(in query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Diacritics and case fall away, so `snimek` finds the Czech default name `Snímek`.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// `describe` returns the words a capture answers to beyond its name: its day, kind and text.
    static func filter(
        _ captures: [ScreenCapture], query: String, by filter: ScreenshotFilter,
        describe: (ScreenCapture) -> [String]
    ) -> [ScreenCapture] {
        let admitted = captures.filter(filter.admits)
        let terms = terms(in: query)
        guard !terms.isEmpty else { return admitted }
        return admitted.filter { capture in
            let haystack = fold(([capture.name] + describe(capture)).joined(separator: "\n"))
            return terms.allSatisfy(haystack.contains)
        }
    }
}
