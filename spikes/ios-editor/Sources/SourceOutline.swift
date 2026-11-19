import Foundation

struct SourceHeading: Sendable, Equatable {
    let range: NSRange
    let level: Int
    let line: Int
    let title: String

    var menuTitle: String { "Level \(level) · line \(line): \(title)" }
}

/// A bounded top-level ATX source outline, not a complete Markdown parser.
/// Titles are literal menu labels. Nothing here resolves or renders markup.
struct SourceOutline: Sendable {
    static let maximumBytes = 65_536
    static let maximumHeadings = 128
    let source: String
    let headings: [SourceHeading]
    let message: String?

    static func make(source: String) -> Self {
        func unavailable(_ message: String) -> Self { Self(source: source, headings: [], message: message) }
        guard source.utf8.prefix(maximumBytes + 1).count <= maximumBytes else {
            return unavailable("Outline unavailable above 64 KiB.")
        }
        let text = source as NSString
        var offset = 0, line = 1
        var fence: (marker: UInt16, count: Int)?
        var headings: [SourceHeading] = []
        while offset < text.length {
            var end = offset
            while end < text.length && text.character(at: end) != 13 && text.character(at: end) != 10 { end += 1 }
            let start = offset + (offset == 0 && text.character(at: 0) == 0xFEFF ? 1 : 0)
            var content = start
            while content < end && text.character(at: content) == 32 { content += 1 }
            let indent = content - start
            let marker: UInt16? = content < end ? text.character(at: content) : nil
            var markerEnd = content
            if marker == 96 || marker == 126 || marker == 35 {
                while markerEnd < end && text.character(at: markerEnd) == marker { markerEnd += 1 }
            }
            let run = markerEnd - content
            let tail = text.substring(with: NSRange(location: markerEnd, length: end - markerEnd))
            if let current = fence {
                if indent <= 3 && marker == current.marker && run >= current.count &&
                    tail.utf16.allSatisfy({ $0 == 32 || $0 == 9 }) { fence = nil }
            } else if indent <= 3 && (marker == 96 || marker == 126) && run >= 3 {
                guard marker != 96 || !tail.utf16.contains(96) else {
                    return unavailable("Outline unavailable for unsupported fence-like source.")
                }
                fence = (marker!, run)
            } else {
                // HTML blocks require parser context. Refuse the entire report
                // instead of presenting possible HTML body text as headings.
                let body = text.substring(with: NSRange(location: start, length: end - start))
                guard !body.contains("<") else { return unavailable("Outline unavailable for HTML-like source.") }
                if indent <= 3 && marker == 35 && (1...6).contains(run) &&
                    (markerEnd == end || text.character(at: markerEnd) == 32 || text.character(at: markerEnd) == 9) {
                    let trimmed = tail.drop(while: { $0 == " " || $0 == "\t" })
                    // Labels are abbreviated visibly; source/ranges stay exact.
                    let safe = String(trimmed.unicodeScalars.map {
                        CharacterSet.controlCharacters.contains($0) || $0 == "\u{2028}" || $0 == "\u{2029}" ? " " : String($0)
                    }.joined())
                    let label = safe.isEmpty ? "(empty heading)" : String(safe.prefix(80)) + (safe.count > 80 ? "…" : "")
                    headings.append(SourceHeading(range: NSRange(location: start, length: end - start),
                                                  level: run, line: line, title: label))
                    guard headings.count <= maximumHeadings else { return unavailable("Outline unavailable above 128 headings.") }
                }
            }
            offset = end
            if offset < text.length {
                let cr = text.character(at: offset) == 13
                offset += 1
                if cr && offset < text.length && text.character(at: offset) == 10 { offset += 1 }
            }
            line += 1
        }
        return Self(source: source, headings: headings, message: headings.isEmpty ? "No top-level ATX headings." : nil)
    }

    /// Heading navigation reuses the selection-only plan and native apply
    /// path of Select source lines: no edit, undo step or generation change.
    func plan(for heading: SourceHeading, selection: NSRange) -> SourceNavigationPlan? {
        guard message == nil, headings.contains(heading) else { return nil }
        return SourceNavigationPlan.make(source: source, selection: selection, destination: heading.range)
    }
}
