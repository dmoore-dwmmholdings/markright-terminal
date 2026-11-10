import Foundation

/// Literal table source from a bounded rectangular TSV selection. This helper
/// does not read a pasteboard, parse Markdown, escape cells or render a grid.
enum MarkdownTableInsertion {
    static let minColumns = 2
    static let maxColumns = 16
    static let minRows = 2
    static let maxRows = 64

    static func make(source: String, selection: NSRange) -> MarkdownInsertionPlan? {
        let sourceBytes = source.utf8.prefix(MarkdownInsertionPlan.maximumSourceBytes + 1).count
        guard sourceBytes <= MarkdownInsertionPlan.maximumSourceBytes,
              SourceSelection.isValid(selection, in: source),
              selection.length <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
        let text = source as NSString
        let selected = text.substring(with: selection)
        let selectedBytes = selected.utf8.prefix(MarkdownInsertionPlan.maximumSelectionBytes + 1).count
        guard selectedBytes <= MarkdownInsertionPlan.maximumSelectionBytes else { return nil }
        let hasLeadingBOM = text.length > 0 && text.character(at: 0) == 0xFEFF
        let previous: UInt16? = selection.location > 0 ? text.character(at: selection.location - 1) : nil
        let atLineStart = selection.location == 0 || previous == 13 || previous == 10
            || (selection.location == 1 && hasLeadingBOM)
        guard atLineStart else { return nil }

        let replacement: String
        let firstCellOffset: Int
        let firstCellLength: Int
        if selection.length == 0 {
            guard !(selection.location == 0 && hasLeadingBOM) else { return nil }
            let next: UInt16? = selection.location < text.length ? text.character(at: selection.location) : nil
            guard next == nil || next == 13 || next == 10 else { return nil }
            let eol = preferredLineEnding(in: source)
            let header = formattedRow(["Column 1", "Column 2"], ending: eol)
            let delimiter = formattedRow(["---", "---"], ending: eol)
            replacement = header + delimiter + formattedRow(["Value 1", "Value 2"], ending: "")
            firstCellOffset = header.utf16.count + delimiter.utf16.count + 2
            firstCellLength = "Value 1".utf16.count
        } else {
            let end = selection.location + selection.length
            let next: UInt16? = end < text.length ? text.character(at: end) : nil
            let last = text.character(at: end - 1)
            guard end == text.length || next == 13 || next == 10 || last == 13 || last == 10 else { return nil }
            let selectedBOM = selection.location == 0 && hasLeadingBOM
            let body = selectedBOM ? (selected as NSString).substring(from: 1) : selected
            guard let rows = physicalRows(in: body), (minRows...maxRows).contains(rows.count),
                  !rows[0].ending.isEmpty else { return nil }
            var grid: [[String]] = []
            var columns: Int?
            var hasContent = false
            for row in rows {
                // At most one excess column is materialized before refusal.
                let cells = row.body.split(separator: "\t", maxSplits: maxColumns, omittingEmptySubsequences: false).map(String.init)
                guard (minColumns...maxColumns).contains(cells.count), columns == nil || columns == cells.count else { return nil }
                columns = cells.count
                for cell in cells {
                    guard !cell.unicodeScalars.contains(where: {
                        $0 == "|" || $0 == "\\" || CharacterSet.controlCharacters.contains($0)
                    }) else { return nil }
                    if !cell.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { hasContent = true }
                }
                grid.append(cells)
            }
            guard hasContent, let columns else { return nil }
            let header = formattedRow(grid[0], ending: rows[0].ending)
            let delimiter = formattedRow(Array(repeating: "---", count: columns), ending: rows[0].ending)
            var output = selectedBOM ? "\u{FEFF}" : ""
            output.append(header)
            output.append(delimiter)
            for index in 1..<rows.count { output.append(formattedRow(grid[index], ending: rows[index].ending)) }
            replacement = output
            firstCellOffset = (selectedBOM ? 1 : 0) + header.utf16.count + delimiter.utf16.count + 2
            firstCellLength = grid[1][0].utf16.count
        }
        let replacementBytes = replacement.utf8.prefix(MarkdownInsertionPlan.maximumSourceBytes + 1).count
        guard replacementBytes <= MarkdownInsertionPlan.maximumSourceBytes,
              sourceBytes - selectedBytes + replacementBytes <= MarkdownInsertionPlan.maximumSourceBytes else { return nil }
        return MarkdownInsertionPlan(source: source, range: selection, replacement: replacement,
            selectionAfter: NSRange(location: selection.location + firstCellOffset, length: firstCellLength))
    }

    private static func formattedRow(_ cells: [String], ending: String) -> String {
        "| " + cells.joined(separator: " | ") + " |" + ending
    }

    private static func physicalRows(in source: String) -> [(body: String, ending: String)]? {
        let scalars = source.unicodeScalars
        var start = scalars.startIndex
        var cursor = start
        var rows: [(body: String, ending: String)] = []
        while cursor < scalars.endIndex {
            if scalars[cursor] == "\r" || scalars[cursor] == "\n" {
                let boundary = cursor
                let isCR = scalars[cursor] == "\r"
                scalars.formIndex(after: &cursor)
                if isCR && cursor < scalars.endIndex && scalars[cursor] == "\n" { scalars.formIndex(after: &cursor) }
                guard rows.count < maxRows else { return nil }
                rows.append((String(scalars[start..<boundary]), String(scalars[boundary..<cursor])))
                start = cursor
            } else {
                scalars.formIndex(after: &cursor)
            }
        }
        // A final ending belongs to its original row, not a phantom empty row.
        if start < scalars.endIndex {
            guard rows.count < maxRows else { return nil }
            rows.append((String(scalars[start..<scalars.endIndex]), ""))
        }
        return rows
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
