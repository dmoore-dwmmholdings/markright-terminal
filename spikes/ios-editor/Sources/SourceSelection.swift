import Foundation

// Original-source UTF-16 coordinates. Do not round an invalid range into a
// different selection, and do not confuse canonical Unicode equality with
// identical source bytes.
enum SourceSelection {
    static let beginning = NSRange(location: 0, length: 0)

    static func sameText(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    static func isValid(_ range: NSRange, in source: String) -> Bool {
        let text = source as NSString
        guard range.location >= 0, range.length >= 0,
              range.location <= text.length, range.length <= text.length - range.location else { return false }
        for offset in [range.location, range.location + range.length] {
            if offset > 0 && offset < text.length {
                let before = text.character(at: offset - 1), after = text.character(at: offset)
                if (0xD800...0xDBFF).contains(before) && (0xDC00...0xDFFF).contains(after) { return false }
                if before == 13 && after == 10 { return false }
            }
        }
        return true
    }
}
