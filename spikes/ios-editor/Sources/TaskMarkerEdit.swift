import Foundation

/// A bounded literal source edit. Only physical row prefixes are inspected;
/// this helper makes no claim about Markdown parser or surrounding context.
enum TaskMarkerEdit {
    static let title = "Toggle task markers"

    static func make(source: String, selection: NSRange) -> MarkdownInsertionPlan? {
        guard source.utf8.prefix(MarkdownInsertionPlan.maximumSourceBytes + 1).count
                <= MarkdownInsertionPlan.maximumSourceBytes,
              SourceSelection.isValid(selection, in: source) else { return nil }
        let text = source as NSString
        let hasLeadingBOM = text.length > 0 && text.character(at: 0) == 0xFEFF
        let range: NSRange
        if selection.length == 0 {
            // A caret immediately before an ending belongs to the current
            // row; immediately after the complete ending it belongs to the next.
            var start = selection.location
            while start > 0 {
                let previous = text.character(at: start - 1)
                if previous == 13 || previous == 10 { break }
                start -= 1
                // Every UTF-16 unit needs at least one UTF-8 byte. Once this
                // partial row alone exceeds the byte budget, no continuation
                // can make the whole row eligible.
                guard selection.location - start <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
            }
            var end = selection.location
            while end < text.length {
                let next = text.character(at: end)
                if next == 13 || next == 10 { break }
                end += 1
                guard end - start <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
            }
            range = NSRange(location: start, length: end - start)
        } else {
            let start = selection.location
            let end = start + selection.length // Validated before addition.
            let previous: UInt16? = start > 0 ? text.character(at: start - 1) : nil
            let next: UInt16? = end < text.length ? text.character(at: end) : nil
            let last = text.character(at: end - 1)
            guard start == 0 || (start == 1 && hasLeadingBOM) || previous == 13 || previous == 10,
                  end == text.length || next == 13 || next == 10 || last == 13 || last == 10 else { return nil }
            range = selection
        }
        // UTF-8 has at least as many bytes as UTF-16 code units. Refuse an
        // oversized row before materializing its substring or replacement.
        guard range.length <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
        let affected = text.substring(with: range)
        guard affected.utf8.prefix(MarkdownInsertionPlan.maximumSelectionBytes + 1).count
                <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
        var bytes = Array(affected.utf8)
        var cursor = 0
        if range.location == 0 && hasLeadingBOM { cursor = 3 }
        var rowCount = 0
        var states: [Int] = []
        var hasUnchecked = false
        while cursor < bytes.count {
            guard rowCount < MarkdownInsertionPlan.maximumPrefixRows else { return nil }
            rowCount += 1
            let start = cursor
            while cursor < bytes.count && bytes[cursor] != 13 && bytes[cursor] != 10 { cursor += 1 }
            let end = cursor
            if !bytes[start..<end].allSatisfy({ $0 == 32 || $0 == 9 }) {
                var marker = start
                while marker < end && bytes[marker] == 32 { marker += 1 }
                guard marker - start <= 3, end - marker >= 5,
                      bytes[marker] == 45 || bytes[marker] == 43 || bytes[marker] == 42,
                      bytes[marker + 1] == 32, bytes[marker + 2] == 91,
                      bytes[marker + 3] == 32 || bytes[marker + 3] == 120 || bytes[marker + 3] == 88,
                      bytes[marker + 4] == 93,
                      marker + 5 == end || bytes[marker + 5] == 32 || bytes[marker + 5] == 9 else { return nil }
                states.append(marker + 3)
                if bytes[marker + 3] == 32 { hasUnchecked = true }
            }
            if cursor < bytes.count {
                let isCR = bytes[cursor] == 13
                cursor += 1
                if isCR && cursor < bytes.count && bytes[cursor] == 10 { cursor += 1 }
            }
        }
        // A final ending belongs to its preceding row, with no extra empty row.
        guard !states.isEmpty else { return nil }
        for state in states {
            if !hasUnchecked { bytes[state] = 32 }
            else if bytes[state] == 32 { bytes[state] = 120 }
        }
        return MarkdownInsertionPlan(source: source, range: range,
            replacement: String(decoding: bytes, as: UTF8.self), selectionAfter: selection,
            originalSelection: selection, actionName: title)
    }
}
