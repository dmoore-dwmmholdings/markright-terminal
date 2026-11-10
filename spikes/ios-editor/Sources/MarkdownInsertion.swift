import Foundation

enum MarkdownInsertionCommand: CaseIterable, Sendable, Equatable {
    case bold
    case italic
    case inlineCode

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .inlineCode: "Inline code"
        }
    }
}

/// A literal source replacement, not a parser, formatting toggle or escaping
/// policy. `source` and `range` describe the exact input this plan may replace.
struct MarkdownInsertionPlan: Sendable {
    static let maximumSourceBytes = 1 * 1024 * 1024
    static let maximumSelectionBytes = 64 * 1024
    let source: String
    let range: NSRange
    let replacement: String
    let selectionAfter: NSRange

    static func make(command: MarkdownInsertionCommand, source: String, selection: NSRange) -> Self? {
        let sourceBytes = source.utf8.prefix(maximumSourceBytes + 1).count
        guard sourceBytes <= maximumSourceBytes,
              SourceSelection.isValid(selection, in: source),
              selection.length <= maximumSelectionBytes else { return nil }
        let selected = (source as NSString).substring(with: selection)
        let selectedBytes = selected.utf8.prefix(maximumSelectionBytes + 1).count
        guard selectedBytes <= maximumSelectionBytes else { return nil }
        let body = selection.length == 0 ? (command == .inlineCode ? "code" : "text") : selected
        let opening: String
        let closing: String
        switch command {
        case .bold:
            opening = "**"
            closing = "**"
        case .italic:
            opening = "*"
            closing = "*"
        case .inlineCode:
            // Whitespace-only selected bodies are refused. No rewriting of
            // whitespace or multiline source is implied by this helper.
            guard !body.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }),
                  !body.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
            var run = 0
            var longest = 0
            for scalar in body.unicodeScalars {
                if scalar == "`" {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 0
                }
            }
            let delimiter = String(repeating: "`", count: longest + 1)
            let padding = body.utf8.first == 0x60 || body.utf8.last == 0x60
                || (body.utf8.first == 0x20 && body.utf8.last == 0x20 && !body.utf8.allSatisfy { $0 == 0x20 })
            opening = delimiter + (padding ? " " : "")
            closing = (padding ? " " : "") + delimiter
        }
        // The body and delimiter are bounded by the selection budget before any
        // replacement is built; the unchanged document is never re-encoded here.
        let replacementBytes = opening.utf8.count + body.utf8.count + closing.utf8.count
        guard replacementBytes <= maximumSourceBytes,
              sourceBytes - selectedBytes + replacementBytes <= maximumSourceBytes else { return nil }
        return Self(source: source, range: selection, replacement: opening + body + closing,
                    selectionAfter: NSRange(location: selection.location + opening.utf16.count,
                                            length: body.utf16.count))
    }

    func matches(source: String, selection: NSRange) -> Bool {
        range == selection && self.source.utf8.elementsEqual(source.utf8)
    }
}
