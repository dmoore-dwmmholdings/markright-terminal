import Foundation

/// In-memory navigation through literal current-source occurrences. No parser,
/// normalization, saved-source index, query history or external access.
struct SourceSelectionFind: Sendable {
    static let maximumSourceBytes = 1_048_576
    static let maximumQueryBytes = 65_536
    static let maximumCandidateChecks = 256
    static let nextTitle = "Next exact occurrence"
    static let previousTitle = "Previous exact occurrence"

    let next: SourceNavigationPlan?
    let previous: SourceNavigationPlan?
    let message: String?

    static func make(source: String, selection: NSRange) -> Self {
        func unavailable(_ message: String) -> Self { Self(next: nil, previous: nil, message: message) }
        guard source.utf8.prefix(maximumSourceBytes + 1).count <= maximumSourceBytes else {
            return unavailable("Find unavailable above 1 MiB of source.")
        }
        guard SourceSelection.isValid(selection, in: source) else {
            return unavailable("Find unavailable for an invalid source selection.")
        }
        guard selection.length > 0 else { return unavailable("Select source text to find exact occurrences.") }
        let text = source as NSString
        let query = text.substring(with: selection)
        guard query.utf8.prefix(maximumQueryBytes + 1).count <= maximumQueryBytes else {
            return unavailable("Find unavailable above 64 KiB of selected text.")
        }
        let before = NSRange(location: 0, length: selection.location)
        let end = selection.location + selection.length
        let after = NSRange(location: end, length: text.length - end)

        // Each direction shares its budget across both wrap segments. A raw
        // match may split CRLF even when the selected query is valid. Skip it
        // with strict UTF-16 progress and keep looking for a valid destination.
        func destination(backwards: Bool) -> (range: NSRange?, limited: Bool) {
            var checked = 0
            let options: String.CompareOptions = backwards ? [.literal, .backwards] : [.literal]
            for segment in (backwards ? [before, after] : [after, before]) {
                var remaining = segment
                while remaining.length > 0 {
                    let match = text.range(of: query, options: options, range: remaining)
                    guard match.location != NSNotFound else { break }
                    guard checked < maximumCandidateChecks else { return (nil, true) }
                    checked += 1
                    if SourceSelection.isValid(match, in: source) { return (match, false) }
                    if backwards {
                        // Keep earlier overlapping raw candidates reachable.
                        remaining.length = match.location + match.length - 1 - remaining.location
                    } else {
                        let upper = remaining.location + remaining.length
                        remaining.location = match.location + 1
                        remaining.length = upper - remaining.location
                    }
                }
            }
            return (nil, false)
        }
        let forward = destination(backwards: false), backward = destination(backwards: true)
        guard !forward.limited && !backward.limited else {
            return unavailable("Find unavailable above 256 candidate checks per direction.")
        }
        guard let nextRange = forward.range, let previousRange = backward.range else {
            return unavailable("No other exact occurrence.")
        }
        return Self(next: SourceNavigationPlan.make(source: source, selection: selection, destination: nextRange),
                    previous: SourceNavigationPlan.make(source: source, selection: selection, destination: previousRange),
                    message: nil)
    }
}
