import Foundation

/// Selects physical source rows literally, including their authored CR/LF
/// endings. No Markdown parsing, normalization or external access is involved.
enum SourceLineSelection {
    static let title = "Select source lines"
    static let maximumSourceBytes = 1_048_576

    static func make(source: String, selection: NSRange) -> SourceNavigationPlan? {
        // Bound the source before an NSString bridge, then validate both
        // endpoints before doing any arithmetic or inspecting adjacent units.
        guard source.utf8.prefix(maximumSourceBytes + 1).count <= maximumSourceBytes,
              SourceSelection.isValid(selection, in: source) else { return nil }
        // The source cap bounds this transient buffer to at most 1,048,576
        // UTF-16 units (about 2 MiB payload), with constant-index row scanning.
        let units = Array(source.utf16)
        var start = selection.location
        while start > 0 {
            let previous = units[start - 1]
            if previous == 13 || previous == 10 { break }
            start -= 1
        }
        // An initial BOM remains outside every destination, even when the
        // original selection included it or the caret preceded it.
        if start == 0 && units.count > 0 && units[0] == 0xFEFF { start = 1 }

        // Nonempty ranges own their last selected code unit, not the untouched
        // next row at their exclusive upper boundary. This anchor may be the
        // LF of a complete selected CRLF; consuming it still ends that row.
        var end = selection.length == 0 ? selection.location : selection.location + selection.length - 1
        while end < units.count {
            let unit = units[end]
            end += 1
            if unit == 13 {
                if end < units.count && units[end] == 10 { end += 1 }
                break
            }
            if unit == 10 { break }
        }
        guard end > start else { return nil }
        let destination = NSRange(location: start, length: end - start)
        guard destination != selection else { return nil }
        return SourceNavigationPlan.make(source: source, selection: selection, destination: destination)
    }
}

/// A selection-only plan captured against the exact source and the current
/// selection. Execution re-checks both, so a stale plan never moves a caret.
struct SourceNavigationPlan: Sendable {
    let source: String
    let selection: NSRange
    let destination: NSRange

    private init(source: String, selection: NSRange, destination: NSRange) {
        self.source = source; self.selection = selection; self.destination = destination
    }

    static func make(source: String, selection: NSRange, destination: NSRange) -> Self? {
        guard SourceSelection.isValid(selection, in: source),
              SourceSelection.isValid(destination, in: source) else { return nil }
        return Self(source: source, selection: selection, destination: destination)
    }

    func matches(source: String, selection: NSRange) -> Bool {
        self.selection == selection && SourceSelection.sameText(self.source, source) &&
            SourceSelection.isValid(destination, in: source)
    }
}
