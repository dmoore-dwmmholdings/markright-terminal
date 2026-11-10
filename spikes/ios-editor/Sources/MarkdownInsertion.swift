import Foundation

enum MarkdownInsertionCommand: CaseIterable, Sendable, Equatable {
    case bold
    case italic
    case inlineCode
    case link
    case imageReference
    case codeBlock

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .inlineCode: "Inline code"
        case .link: "Link"
        case .imageReference: "Image reference"
        case .codeBlock: "Code block"
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
        let placeholder: String
        switch command {
        case .bold, .italic: placeholder = "text"
        case .inlineCode, .codeBlock: placeholder = "code"
        case .link: placeholder = "link text"
        case .imageReference: placeholder = "alt text"
        }
        let body = selection.length == 0 ? placeholder : selected
        let opening: String
        let closing: String
        var selectionOffset: Int?
        var selectionLength: Int?
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
            let delimiter = String(repeating: "`", count: longestBacktickRun(in: body) + 1)
            let padding = body.utf8.first == 0x60 || body.utf8.last == 0x60
                || (body.utf8.first == 0x20 && body.utf8.last == 0x20 && !body.utf8.allSatisfy { $0 == 0x20 })
            opening = delimiter + (padding ? " " : "")
            closing = (padding ? " " : "") + delimiter
        case .link, .imageReference:
            guard !body.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || $0 == "[" || $0 == "]" || $0 == "\\"
            }), !body.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
            opening = command == .link ? "[" : "!["
            closing = "](destination)"
            selectionOffset = opening.utf16.count + body.utf16.count + 2
            selectionLength = "destination".utf16.count
        case .codeBlock:
            let eol = preferredLineEnding(in: source)
            let text = source as NSString
            let previous: UInt16? = selection.location > 0 ? text.character(at: selection.location - 1) : nil
            let atLineStart = selection.location == 0 || previous == 13 || previous == 10
            let end = selection.location + selection.length
            let next: UInt16? = end < text.length ? text.character(at: end) : nil
            let needsSuffixEnding = next != nil && next != 13 && next != 10
            let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: body) + 1))
            opening = (atLineStart ? "" : eol) + fence + eol
            let bodyHasEnding = body.utf8.last == 13 || body.utf8.last == 10
            closing = (bodyHasEnding ? "" : eol) + fence + (needsSuffixEnding ? eol : "")
        }
        // The body and delimiter are bounded by the selection budget before any
        // replacement is built; the unchanged document is never re-encoded here.
        let replacementBytes = opening.utf8.count + body.utf8.count + closing.utf8.count
        guard replacementBytes <= maximumSourceBytes,
              sourceBytes - selectedBytes + replacementBytes <= maximumSourceBytes else { return nil }
        return Self(source: source, range: selection, replacement: opening + body + closing,
                    selectionAfter: NSRange(location: selection.location + (selectionOffset ?? opening.utf16.count),
                                            length: selectionLength ?? body.utf16.count))
    }

    func matches(source: String, selection: NSRange) -> Bool {
        range == selection && self.source.utf8.elementsEqual(source.utf8)
    }

    private static func longestBacktickRun(in body: String) -> Int {
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
        return longest
    }

    private static func preferredLineEnding(in source: String) -> String {
        let scalars = source.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == "\r" {
                let next = scalars.index(after: index)
                return next < scalars.endIndex && scalars[next] == "\n" ? "\r\n" : "\r"
            }
            if scalars[index] == "\n" { return "\n" }
            scalars.formIndex(after: &index)
        }
        return "\n"
    }
}
