import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class SourceLineSelectionTests: XCTestCase {
    private func verify(_ source: String, selection: NSRange, destination: NSRange, selected: String,
                        file: StaticString = #filePath, line: UInt = #line) throws -> SourceNavigationPlan {
        let plan = try XCTUnwrap(SourceLineSelection.make(source: source, selection: selection), file: file, line: line)
        XCTAssertEqual(plan.selection, selection, file: file, line: line)
        XCTAssertEqual(plan.destination, destination, file: file, line: line)
        XCTAssertTrue(plan.source.utf8.elementsEqual(source.utf8), file: file, line: line)
        XCTAssertTrue((source as NSString).substring(with: plan.destination).utf8.elementsEqual(selected.utf8), file: file, line: line)
        XCTAssertTrue(SourceSelection.isValid(plan.destination, in: source), file: file, line: line)
        XCTAssertTrue(plan.matches(source: source, selection: selection), file: file, line: line)
        return plan
    }

    func testEveryValidCaretPositionSelectsCurrentRowIncludingMixedEndingsAndEOF() throws {
        let rows: [(body: String, ending: String)] = [
            ("\u{FEFF}Cafe\u{301} 😀", "\r\n"),
            ("second 😀", "\r"),
            ("third e\u{301}", "\n"),
            ("last 😀", "")
        ]
        let source = rows.map { $0.body + $0.ending }.joined()
        var start = 0
        for row in rows {
            let hasBOM = start == 0
            let destination = NSRange(location: start + (hasBOM ? 1 : 0),
                length: row.body.utf16.count + row.ending.utf16.count - (hasBOM ? 1 : 0))
            let selected = (hasBOM ? String(row.body.dropFirst()) : row.body) + row.ending
            for offset in 0...row.body.utf16.count {
                let caret = NSRange(location: start + offset, length: 0)
                if SourceSelection.isValid(caret, in: source) {
                    _ = try verify(source, selection: caret, destination: destination, selected: selected)
                }
            }
            start += row.body.utf16.count + row.ending.utf16.count
        }
    }

    func testCaretAtEndingBelongsToCurrentRowAndAfterEndingBelongsToNext() throws {
        for ending in ["\r", "\n", "\r\n"] {
            let first = "first" + ending
            let source = first + "next"
            _ = try verify(source, selection: NSRange(location: 5, length: 0),
                destination: NSRange(location: 0, length: first.utf16.count), selected: first)
            _ = try verify(source, selection: NSRange(location: first.utf16.count, length: 0),
                destination: NSRange(location: first.utf16.count, length: 4), selected: "next")
            let endingSelection = NSRange(location: 5, length: ending.utf16.count)
            _ = try verify(source, selection: endingSelection,
                destination: NSRange(location: 0, length: first.utf16.count), selected: first)
        }
    }

    func testHalfOpenSelectionEndingAtNextRowStartNeverIncludesUntouchedRow() throws {
        for ending in ["\r", "\n", "\r\n"] {
            let first = "first" + ending
            let second = "second" + ending
            let source = first + second + "third"
            _ = try verify(source, selection: NSRange(location: 2, length: first.utf16.count - 2),
                destination: NSRange(location: 0, length: first.utf16.count), selected: first)
            _ = try verify(source, selection: NSRange(location: 2, length: first.utf16.count + second.utf16.count - 2),
                destination: NSRange(location: 0, length: first.utf16.count + second.utf16.count), selected: first + second)
            // Selecting one unit of the following body now touches that row.
            _ = try verify(source, selection: NSRange(location: 2, length: first.utf16.count - 1),
                destination: NSRange(location: 0, length: first.utf16.count + second.utf16.count), selected: first + second)
        }
    }

    func testPartialSelectionExpandsAllTouchedRowsAndPreservesUTF16Coordinates() throws {
        let prefix = "outside\r\n"
        let first = "Cafe\u{301} 😀\r"
        let second = "\t \n"
        let third = "last 😀\r\n"
        let source = prefix + first + second + third + "after"
        let start = prefix.utf16.count
        let firstDestination = NSRange(location: start, length: first.utf16.count)
        _ = try verify(source, selection: NSRange(location: start + 4, length: 1),
            destination: firstDestination, selected: first) // Combining scalar alone.
        let thirdStart = start + first.utf16.count + second.utf16.count
        _ = try verify(source, selection: NSRange(location: start + 2, length: thirdStart + 2 - start - 2),
            destination: NSRange(location: start, length: first.utf16.count + second.utf16.count + third.utf16.count),
            selected: first + second + third)
        let emoji = (source as NSString).range(of: "😀")
        _ = try verify(source, selection: emoji, destination: firstDestination, selected: first)
    }

    func testLeadingBOMIsAlwaysExcludedWhileInternalBOMStaysLiteral() throws {
        let first = "\u{FEFF}first\r\n"
        let last = "\u{FEFF}last"
        let source = first + last
        let firstDestination = NSRange(location: 1, length: first.utf16.count - 1)
        for selection in [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0),
                          NSRange(location: 0, length: 1), NSRange(location: 0, length: first.utf16.count)] {
            _ = try verify(source, selection: selection, destination: firstDestination, selected: "first\r\n")
        }
        _ = try verify(source, selection: NSRange(location: 0, length: source.utf16.count),
            destination: NSRange(location: 1, length: source.utf16.count - 1), selected: "first\r\n" + last)
        _ = try verify(source, selection: NSRange(location: first.utf16.count, length: 0),
            destination: NSRange(location: first.utf16.count, length: last.utf16.count), selected: last)
    }

    func testBlankRowsSelectTheirEndingWithoutSelectingPreviousOrNextRows() throws {
        let source = "before\r\n\r\n\n \t\rafter"
        let blankStart = "before\r\n".utf16.count
        _ = try verify(source, selection: NSRange(location: blankStart, length: 0),
            destination: NSRange(location: blankStart, length: 2), selected: "\r\n")
        _ = try verify(source, selection: NSRange(location: blankStart + 2, length: 0),
            destination: NSRange(location: blankStart + 2, length: 1), selected: "\n")
        _ = try verify(source, selection: NSRange(location: blankStart + 4, length: 0),
            destination: NSRange(location: blankStart + 3, length: 3), selected: " \t\r")
        _ = try verify("\u{FEFF}\r\n", selection: NSRange(location: 0, length: 0),
            destination: NSRange(location: 1, length: 2), selected: "\r\n")
    }

    func testEmptyEOFRowsEmptyDocumentsAndAlreadyExpandedSelectionsAreNoOps() {
        for source in ["", "\u{FEFF}"] {
            for offset in 0...source.utf16.count {
                XCTAssertNil(SourceLineSelection.make(source: source, selection: NSRange(location: offset, length: 0)))
            }
            XCTAssertNil(SourceLineSelection.make(source: source, selection: NSRange(location: 0, length: source.utf16.count)))
        }
        for source in ["first\r", "first\n", "first\r\n", "\r\n", "\u{FEFF}\n"] {
            XCTAssertNil(SourceLineSelection.make(source: source, selection: NSRange(location: source.utf16.count, length: 0)))
        }
        for source in ["first", "first\r\n", "first\nsecond\r", "\r\n", " \t\r"] {
            XCTAssertNil(SourceLineSelection.make(source: source, selection: NSRange(location: 0, length: source.utf16.count)))
        }
        let bom = "\u{FEFF}first\r\n"
        XCTAssertNil(SourceLineSelection.make(source: bom, selection: NSRange(location: 1, length: bom.utf16.count - 1)))
        let source = "first\nsecond\r\nthird"
        XCTAssertNil(SourceLineSelection.make(source: source, selection: NSRange(location: 6, length: "second\r\n".utf16.count)))
    }

    func testInvalidSurrogateCRLFPartialAndOverflowRangesAreRefusedWithoutRounding() {
        let source = "😀\r\nlast"
        for selection in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
                          NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: NSNotFound),
                          NSRange(location: Int.max, length: Int.max), NSRange(location: 2, length: Int.max),
                          NSRange(location: source.utf16.count + 1, length: 0),
                          NSRange(location: source.utf16.count, length: 1),
                          NSRange(location: 1, length: 0), NSRange(location: 0, length: 1),
                          NSRange(location: 1, length: 1), NSRange(location: 3, length: 0),
                          NSRange(location: 0, length: 3), NSRange(location: 3, length: 1)] {
            XCTAssertNil(SourceLineSelection.make(source: source, selection: selection), String(describing: selection))
        }
    }

    func testExactOneMiBUTF8SourceBoundaryAndOneByteOverWithLargeUnicodeRow() throws {
        let source = "e\u{301}\n" + String(repeating: "😀", count: 262_143)
        XCTAssertEqual(source.utf8.count, SourceLineSelection.maximumSourceBytes)
        let destination = NSRange(location: 3, length: source.utf16.count - 3)
        let caret = NSRange(location: source.utf16.count, length: 0)
        let plan = try XCTUnwrap(SourceLineSelection.make(source: source, selection: caret))
        XCTAssertEqual(plan.destination, destination)
        XCTAssertEqual(plan.selection, caret)
        XCTAssertTrue(plan.source.utf8.elementsEqual(source.utf8))
        XCTAssertNil(SourceLineSelection.make(source: source + "a", selection: caret))
        let ascii = String(repeating: "a", count: SourceLineSelection.maximumSourceBytes)
        XCTAssertEqual(SourceLineSelection.make(source: ascii, selection: NSRange(location: 0, length: 0))?.destination,
            NSRange(location: 0, length: ascii.utf16.count))
        XCTAssertNil(SourceLineSelection.make(source: ascii + "a", selection: NSRange(location: 0, length: 0)))
    }

    func testCapturedPlanRejectsStaleOriginalSelectionAndCanonicalEquivalentSourceBytes() throws {
        let source = "\u{FEFF}Café 😀\r\nafter"
        let selection = NSRange(location: 3, length: 1)
        let plan = try verify(source, selection: selection,
            destination: NSRange(location: 1, length: "Café 😀\r\n".utf16.count), selected: "Café 😀\r\n")
        XCTAssertFalse(plan.matches(source: source, selection: plan.destination))
        XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 4, length: 0)))
        XCTAssertFalse(plan.matches(source: "\u{FEFF}Cafe\u{301} 😀\r\nafter", selection: selection))
        XCTAssertFalse(plan.matches(source: "\u{FEFF}Café 😀\nafter", selection: selection))
        XCTAssertFalse(plan.matches(source: source + "x", selection: selection))
        XCTAssertFalse(plan.matches(source: "\u{FEFF}Café 😀\r\nAfter", selection: selection))
    }

    func testSourceCodeURIsAndUnicodeSeparatorsRemainLiteralPhysicalRowContent() throws {
        let prefix = "```\r\n"
        let body = "<script>inert()</script> [link](https://example.invalid) file:///tmp/item\u{2028}still\u{2029}same row\r\n"
        let source = prefix + body + "```"
        _ = try verify(source, selection: NSRange(location: prefix.utf16.count + 5, length: 0),
            destination: NSRange(location: prefix.utf16.count, length: body.utf16.count), selected: body)
        XCTAssertEqual(SourceLineSelection.title, "Select source lines")
    }
}
