import Foundation

enum SourcePreviewState: Equatable {
    case ready
    case composing
    case tooLarge
    case tooManyRows
    case invalidSelection
}

struct SourcePreviewRow: Identifiable {
    let id: Int
    let source: String
    let separatorAfter: String
    let range: NSRange
    let isActive: Bool
    let isLiteral: Bool
    let display: AttributedString
}

/// A bounded, disposable projection of the existing fixture groups. It is not a
/// Markdown parser, an editor model or a source of callbacks into an editor.
struct SourcePreviewProjection {
    static let maximumBytes = 65_536
    static let maximumRows = 256
    static let maximumInlineUTF16 = 4096
    let state: SourcePreviewState
    let rows: [SourcePreviewRow]
    let message: String?

    @MainActor static func make(source: String, selection: NSRange, composing: Bool) -> Self {
        // Composition must not invoke grouping or attributed Markdown parsing.
        guard !composing else {
            return Self(state: .composing, rows: [], message: "Preview paused while typing.")
        }
        guard source.utf8.prefix(maximumBytes + 1).count <= maximumBytes else {
            return Self(state: .tooLarge, rows: [], message: "Preview is unavailable for this source size.")
        }
        guard SourceSelection.isValid(selection, in: source) else {
            return Self(state: .invalidSelection, rows: [], message: "Preview is unavailable for the current selection.")
        }
        let blocks = EditorModel(source: source).blocks
        guard blocks.count <= maximumRows else {
            return Self(state: .tooManyRows, rows: [], message: "Preview is unavailable for this many source rows.")
        }
        // The fixture grouper recognizes only its atomic backtick blocks. A
        // fence-like marker elsewhere makes context uncertain for every row;
        // keep the whole report literal rather than parse a possible code body.
        let unsupportedFence = blocks.contains {
            !$0.atomic && ($0.source.contains("~~~") || $0.source.contains("```"))
        }
        let sourceLength = source.utf16.count
        let selectionEnd = selection.location + selection.length
        var offset = 0
        var rows: [SourcePreviewRow] = []
        for (index, block) in blocks.enumerated() {
            let bodyLength = block.source.utf16.count
            let length = bodyLength + block.separatorAfter.utf16.count
            let end = offset + length
            let active: Bool
            if selection.length == 0 {
                active = (selection.location >= offset && selection.location < end)
                    || (selection.location == sourceLength && index == blocks.count - 1)
            } else {
                active = selection.location < end && selectionEnd > offset && length > 0
            }
            let literal = unsupportedFence || active || block.atomic || bodyLength > maximumInlineUTF16
                || ["<", "![", "```", "~~~", "{%", "{{"].contains(where: { block.source.contains($0) })
            var display: AttributedString
            if literal || block.source.isEmpty {
                display = AttributedString(block.source)
            } else {
                display = EditorModel.previewText(block.source)
            }
            // Defend both paths, even if the inline preview implementation later
            // changes. These rows supply readable text, not URL actions.
            display.link = nil
            rows.append(SourcePreviewRow(id: offset, source: block.source, separatorAfter: block.separatorAfter,
                range: NSRange(location: offset, length: length), isActive: active, isLiteral: literal, display: display))
            offset = end
        }
        return Self(state: .ready, rows: rows,
                    message: unsupportedFence ? "Unsupported fence-like syntax; preview remains literal." : nil)
    }
}
