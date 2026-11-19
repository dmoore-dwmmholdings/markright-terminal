import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class TaskMarkerEditTests: XCTestCase {
    private func fullRange(_ source: String) -> NSRange {
        NSRange(location: 0, length: source.utf16.count)
    }

    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    private func verify(_ source: String, selection: NSRange, expected: String,
                        file: StaticString = #filePath, line: UInt = #line) throws -> MarkdownInsertionPlan {
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: selection), file: file, line: line)
        bytesEqual(plan.source, source, file: file, line: line)
        bytesEqual(apply(plan), expected, file: file, line: line)
        XCTAssertEqual(plan.originalSelection, selection, file: file, line: line)
        XCTAssertEqual(plan.selectionAfter, selection, file: file, line: line)
        XCTAssertEqual(plan.actionName, "Toggle task markers", file: file, line: line)
        XCTAssertTrue(plan.restoresSelectionOnUndo, file: file, line: line)
        XCTAssertEqual(plan.replacement.utf16.count, plan.range.length, file: file, line: line)
        XCTAssertEqual(apply(plan).utf16.count, source.utf16.count, file: file, line: line)
        XCTAssertTrue(plan.matches(source: source, selection: selection), file: file, line: line)
        XCTAssertTrue(SourceSelection.isValid(plan.selectionAfter, in: apply(plan)), file: file, line: line)
        return plan
    }

    func testMixedBatchPreservesBOMNFDUnicodeBlankRowsAndPhysicalEndings() throws {
        let source = "\u{FEFF}  - [ ] Cafe\u{301} 😀\r\n \t\r+ [X]\n* [x]\r\n- [ ]\tlast"
        let expected = "\u{FEFF}  - [x] Cafe\u{301} 😀\r\n \t\r+ [X]\n* [x]\r\n- [x]\tlast"
        let plan = try verify(source, selection: fullRange(source), expected: expected)
        XCTAssertEqual(plan.range, fullRange(source))
        _ = try verify(source, selection: NSRange(location: 1, length: source.utf16.count - 1), expected: expected)
        let cleared = "\u{FEFF}  - [ ] Cafe\u{301} 😀\r\n \t\r+ [ ]\n* [ ]\r\n- [ ]\tlast"
        _ = try verify(expected, selection: fullRange(expected), expected: cleared)
    }

    func testEveryValidCaretPositionOnARowIncludesItsEndAndPreservesSelection() throws {
        let rows: [(body: String, ending: String, changed: String)] = [
            ("\u{FEFF}- [ ] e\u{301} 😀", "\r\n", "\u{FEFF}- [x] e\u{301} 😀"),
            ("+ [X] second", "\r", "+ [ ] second"),
            ("  * [x]\tthird", "\n", "  * [ ]\tthird"),
            ("- [ ]", "", "- [x]")
        ]
        let source = rows.map { $0.body + $0.ending }.joined()
        var start = 0
        for row in rows {
            let range = NSRange(location: start, length: row.body.utf16.count)
            let expected = (source as NSString).replacingCharacters(in: range, with: row.changed)
            for offset in 0...row.body.utf16.count {
                let caret = NSRange(location: start + offset, length: 0)
                if SourceSelection.isValid(caret, in: source) {
                    let plan = try verify(source, selection: caret, expected: expected)
                    XCTAssertEqual(plan.range, range)
                    if caret != range { XCTAssertFalse(plan.matches(source: source, selection: range)) }
                }
            }
            start += row.body.utf16.count + row.ending.utf16.count
        }
    }

    func testCaretAfterEndingBelongsToNextRowIncludingEmptyEOFRows() throws {
        for ending in ["\r", "\n", "\r\n"] {
            let first = "- [ ] first"
            let source = first + ending + "+ [X] next"
            _ = try verify(source, selection: NSRange(location: first.utf16.count, length: 0),
                expected: "- [x] first" + ending + "+ [X] next")
            _ = try verify(source, selection: NSRange(location: (first + ending).utf16.count, length: 0),
                expected: first + ending + "+ [ ] next")
            let trailing = first + ending
            XCTAssertNil(TaskMarkerEdit.make(source: trailing, selection: NSRange(location: trailing.utf16.count, length: 0)))
            _ = try verify(trailing, selection: fullRange(trailing), expected: "- [x] first" + ending)
        }
        for source in ["", "\u{FEFF}", " \t", "\r\n", "\u{FEFF}\t\r\n"] {
            XCTAssertNil(TaskMarkerEdit.make(source: source, selection: NSRange(location: source.utf16.count, length: 0)))
        }
    }

    func testWholeRowsMayEndBeforeOrAfterTheirEndingAndLeaveSurroundingsUntouched() throws {
        for ending in ["\r", "\n", "\r\n"] {
            let prefix = "outside" + ending
            let body = " - [ ] one" + ending + "\t " + ending + "* [X] two"
            let suffix = ending + "after"
            let source = prefix + body + suffix
            let changed = " - [x] one" + ending + "\t " + ending + "* [X] two"
            for extra in [0, ending.utf16.count] {
                let range = NSRange(location: prefix.utf16.count, length: body.utf16.count + extra)
                let plan = try verify(source, selection: range, expected: prefix + changed + suffix)
                XCTAssertEqual(plan.range, range)
            }
        }
    }

    func testAllBulletFormsIndentationsAndMinimalMarkersAreAcceptedLiterally() throws {
        for bullet in ["-", "+", "*"] {
            for spaces in 0...3 {
                let prefix = String(repeating: " ", count: spaces) + bullet
                for suffix in ["", " text", "\ttext", "  two spaces"] {
                    let source = prefix + " [ ]" + suffix
                    _ = try verify(source, selection: fullRange(source), expected: prefix + " [x]" + suffix)
                    let checked = prefix + " [X]" + suffix
                    _ = try verify(checked, selection: fullRange(checked), expected: prefix + " [ ]" + suffix)
                }
            }
        }
        let source = "\u{FEFF}   - [ ] first"
        _ = try verify(source, selection: NSRange(location: 0, length: 0), expected: "\u{FEFF}   - [x] first")
    }

    func testUnsupportedRowsAndAllBlankSelectionsAreAtomicallyRefused() {
        for row in ["text", "- item", "- [ ]tail", "- [ ]\u{A0}tail", "-  [ ] text", "-\t[ ] text",
                    "- [  ] text", "- [y] text", "- [✓] text", "- [\t] text", "- [x text",
                    "    - [ ] text", "\t- [ ] text", " \t- [ ] text", "\u{A0}- [ ] text",
                    "1. [ ] text", "> - [ ] text", "\\- [ ] text", "\u{FEFF}- [ ] text",
                    "\u{A0}", "\u{2028}"] {
            let source = "- [ ] valid\r\n" + row + "\n+ [x] valid"
            XCTAssertNil(TaskMarkerEdit.make(source: source, selection: fullRange(source)), String(reflecting: row))
        }
        for source in ["", " ", "\t", "\r\n", " \t\r\n\t\r ", "\u{FEFF} \t\r\n"] {
            XCTAssertNil(TaskMarkerEdit.make(source: source, selection: fullRange(source)))
        }
        let overIndentedBOM = "\u{FEFF}    - [ ] text"
        XCTAssertNil(TaskMarkerEdit.make(source: overIndentedBOM, selection: fullRange(overIndentedBOM)))
    }

    func testInvalidPartialOverflowSurrogateAndCRLFRangesAreRefusedWithoutRounding() {
        let source = "- [ ] 😀\r\n+ [x] end"
        let text = source as NSString
        let emoji = text.range(of: "😀").location
        let cr = text.range(of: "\r\n").location
        for range in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: NSNotFound),
                      NSRange(location: Int.max, length: Int.max), NSRange(location: 2, length: Int.max),
                      NSRange(location: text.length + 1, length: 0), NSRange(location: 1, length: text.length - 1),
                      NSRange(location: 0, length: text.length - 1), NSRange(location: emoji + 1, length: 0),
                      NSRange(location: 0, length: emoji + 1), NSRange(location: cr + 1, length: 0),
                      NSRange(location: 0, length: cr + 1), NSRange(location: cr + 1, length: text.length - cr - 1)] {
            XCTAssertNil(TaskMarkerEdit.make(source: source, selection: range), String(describing: range))
        }
        // This valid UTF-16 boundary inside a combining sequence is still a
        // partial row for a nonempty selection, so it must not be expanded.
        let nfd = "- [ ] e\u{301}nd"
        XCTAssertNil(TaskMarkerEdit.make(source: nfd, selection: NSRange(location: 7, length: nfd.utf16.count - 7)))
    }

    func testPhysicalRowLimitCountsBlankRowsAndDoesNotInventATrailingRow() throws {
        let limit = MarkdownInsertionPlan.maximumPrefixRows
        let boundary = "- [ ] first\r\n" + String(repeating: " \t\n", count: limit - 1)
        _ = try verify(boundary, selection: fullRange(boundary),
            expected: "- [x] first\r\n" + String(repeating: " \t\n", count: limit - 1))
        let over = boundary + "\r"
        XCTAssertNil(TaskMarkerEdit.make(source: over, selection: fullRange(over)))
        let allTasks = String(repeating: "- [X]\r\n", count: limit)
        _ = try verify(allTasks, selection: fullRange(allTasks), expected: String(repeating: "- [ ]\r\n", count: limit))
        XCTAssertNil(TaskMarkerEdit.make(source: allTasks + "- [x]", selection: fullRange(allTasks + "- [x]")))
    }

    func testExactAffectedByteBoundaryIncludesSelectedBOMAndEndings() throws {
        let limit = MarkdownInsertionPlan.maximumSelectionBytes
        let fixed = "\u{FEFF}- [ ] \r\n"
        let emoji = String(repeating: "😀", count: (limit - fixed.utf8.count) / 4)
        let fill = String(repeating: "a", count: limit - fixed.utf8.count - emoji.utf8.count)
        let source = "\u{FEFF}- [ ] " + emoji + fill + "\r\n"
        XCTAssertEqual(source.utf8.count, limit)
        _ = try verify(source, selection: fullRange(source), expected: "\u{FEFF}- [x] " + emoji + fill + "\r\n")
        let over = "\u{FEFF}- [ ] " + emoji + fill + "a\r\n"
        XCTAssertNil(TaskMarkerEdit.make(source: over, selection: fullRange(over)))

        let row = "- [ ] " + String(repeating: "a", count: limit - 6)
        let withEnding = row + "\r\n"
        let caret = NSRange(location: 4, length: 0)
        let plan = try verify(withEnding, selection: caret,
            expected: "- [x] " + String(repeating: "a", count: limit - 6) + "\r\n")
        XCTAssertEqual(plan.range, fullRange(row)) // Ending is outside the replacement budget.
        XCTAssertNil(TaskMarkerEdit.make(source: withEnding, selection: fullRange(withEnding)))
        XCTAssertNil(TaskMarkerEdit.make(source: row + "a", selection: caret))
    }

    func testCaretRowBudgetAtBeginningMiddleAndEndPreservesExactBoundary() throws {
        let limit = MarkdownInsertionPlan.maximumSelectionBytes
        let exact = "- [ ] " + String(repeating: "a", count: limit - 6)
        let changed = "- [x] " + String(repeating: "a", count: limit - 6)
        for location in [0, limit / 2, limit] {
            _ = try verify(exact + "\r\n", selection: NSRange(location: location, length: 0), expected: changed + "\r\n")
        }
        // Both row-discovery directions must refuse an ineligible row; the
        // outside rows and their original CRLF/CR separators remain untouched.
        let prefix = "outside\r\n", oversized = exact + "a", suffix = "\rafter"
        let source = prefix + oversized + suffix
        for offset in [0, oversized.utf16.count / 2, oversized.utf16.count] {
            XCTAssertNil(TaskMarkerEdit.make(source: source,
                selection: NSRange(location: prefix.utf16.count + offset, length: 0)))
        }
        // UTF-16 length alone is not the byte limit: supplementary text still
        // requires the authoritative UTF-8 check after bounded discovery.
        let wide = "- [ ] " + String(repeating: "😀", count: limit / 4)
        XCTAssertLessThan(wide.utf16.count, limit)
        XCTAssertGreaterThan(wide.utf8.count, limit)
        for location in [0, wide.utf16.count] {
            XCTAssertNil(TaskMarkerEdit.make(source: wide, selection: NSRange(location: location, length: 0)))
        }
    }

    func testExactOneMiBSourceBoundaryAllowsSmallEditButRefusesOneMoreByte() throws {
        let task = "- [ ] Café 😀"
        let limit = MarkdownInsertionPlan.maximumSourceBytes
        let prefix = String(repeating: "a", count: limit - task.utf8.count - 1) + "\n"
        let source = prefix + task
        XCTAssertEqual(source.utf8.count, limit)
        let caret = NSRange(location: source.utf16.count, length: 0)
        _ = try verify(source, selection: caret, expected: prefix + "- [x] Café 😀")
        XCTAssertNil(TaskMarkerEdit.make(source: "a" + source,
            selection: NSRange(location: caret.location + 1, length: 0)))
        let selection = NSRange(location: prefix.utf16.count, length: task.utf16.count)
        XCTAssertNotNil(TaskMarkerEdit.make(source: source, selection: selection))
    }

    func testStaleGuardUsesOriginalSelectionAndExactBytesIncludingCanonicalEquivalents() throws {
        let source = "- [ ] Café 😀\r\n"
        let caret = NSRange(location: 3, length: 0)
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: caret))
        XCTAssertNotEqual(plan.range, caret)
        XCTAssertTrue(plan.matches(source: source, selection: caret))
        XCTAssertFalse(plan.matches(source: source, selection: plan.range))
        XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 4, length: 0)))
        XCTAssertFalse(plan.matches(source: "- [ ] Cafe\u{301} 😀\r\n", selection: caret))
        XCTAssertFalse(plan.matches(source: "- [ ] Café 😀\n", selection: caret))
        XCTAssertFalse(plan.matches(source: source + "x", selection: caret))
        XCTAssertFalse(plan.matches(source: "- [x] Café 😀\r\n", selection: caret))
    }

    func testExistingPlanInitializerAndInsertionFactoryKeepTheirDefaults() throws {
        let range = NSRange(location: 1, length: 2)
        let manual = MarkdownInsertionPlan(source: "abcd", range: range, replacement: "XY", selectionAfter: range)
        XCTAssertEqual(manual.originalSelection, range)
        XCTAssertEqual(manual.actionName, "Insert Markdown")
        XCTAssertFalse(manual.restoresSelectionOnUndo)
        XCTAssertTrue(manual.matches(source: "abcd", selection: range))
        let insertion = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: "abcd", selection: range))
        XCTAssertEqual(insertion.originalSelection, range)
        XCTAssertEqual(insertion.actionName, "Insert Markdown")
        XCTAssertFalse(insertion.restoresSelectionOnUndo)
        XCTAssertEqual(TaskMarkerEdit.title, "Toggle task markers")
        XCTAssertFalse(MarkdownInsertionCommand.allCases.map(\.title).contains(TaskMarkerEdit.title))
    }

    func testCapabilityShapedBodiesAndMarkdownContextsAreOnlyLiteralSource() throws {
        let source = "```\n- [ ] [link](https://example.invalid) ![image](file:///tmp/item) <script>inert()</script>\n```"
        let start = "```\n".utf16.count
        let body = "- [ ] [link](https://example.invalid) ![image](file:///tmp/item) <script>inert()</script>"
        _ = try verify(source, selection: NSRange(location: start, length: body.utf16.count),
            expected: "```\n- [x] [link](https://example.invalid) ![image](file:///tmp/item) <script>inert()</script>\n```")
        XCTAssertNil(TaskMarkerEdit.make(source: source, selection: fullRange(source)))
    }

    func testToggleTwiceOnUncheckedRowsRestoresExactOriginalBytes() throws {
        let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n\r\n  * [ ]\ttwo\n+ [ ]"
        let checked = "\u{FEFF}- [x] Cafe\u{301} 😀\r\n\r\n  * [x]\ttwo\n+ [x]"
        let once = apply(try verify(source, selection: fullRange(source), expected: checked))
        let twice = apply(try verify(once, selection: fullRange(once), expected: source))
        bytesEqual(twice, source)
        // Uppercase X is cleared, not restored: a toggle round trip is exact
        // only from all-unchecked rows. Undo is the exact path for the rest.
        let upper = "+ [X] a\n- [ ] b"
        let upperOnce = apply(try verify(upper, selection: fullRange(upper), expected: "+ [X] a\n- [x] b"))
        _ = try verify(upperOnce, selection: fullRange(upperOnce), expected: "+ [ ] a\n- [ ] b")
    }

    /// Models the native editors' undo registration on a plain text model: the
    /// text step plus selection-only steps registered before and after it. It
    /// checks that the group ordering yields the exact bytes and selection.
    @MainActor func testUndoGroupOrderingRestoresExactBytesAndOriginalSelection() throws {
        let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n* [x] two\r"
        let caret = NSRange(location: 9, length: 0)
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: caret))
        XCTAssertNotEqual(plan.range, caret, "Caret plan should expand to its whole row")
        let undo = UndoManager(); undo.groupsByEvent = false
        let model = UndoOrderingModel(source, caret, undo)
        undo.beginUndoGrouping()
        model.registerSelection(select: plan.originalSelection, reverse: nil)
        model.registerText(range: plan.range, replacement: plan.replacement)
        model.text = (model.text as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
        model.selection = plan.selectionAfter
        model.registerSelection(select: nil, reverse: plan.selectionAfter)
        undo.endUndoGrouping()
        let edited = model.text
        bytesEqual(edited, "\u{FEFF}- [x] Cafe\u{301} 😀\r\n* [x] two\r")
        for _ in 0..<3 {
            undo.undo()
            XCTAssertEqual(Array(model.text.utf8), Array(source.utf8))
            XCTAssertEqual(model.selection, caret)
            undo.redo()
            XCTAssertEqual(Array(model.text.utf8), Array(edited.utf8))
            XCTAssertEqual(model.selection, plan.selectionAfter)
        }
        undo.undo()
        XCTAssertFalse(undo.canUndo)
        XCTAssertTrue(undo.canRedo)
    }
}

/// Plain text model mirroring a text view: undoing a replacement selects the
/// whole restored range, so only the selection-only steps can restore a caret.
@MainActor private final class UndoOrderingModel {
    var text: String
    var selection: NSRange
    let undo: UndoManager
    init(_ text: String, _ selection: NSRange, _ undo: UndoManager) {
        self.text = text; self.selection = selection; self.undo = undo
    }

    func registerText(range: NSRange, replacement: String) {
        let old = (text as NSString).substring(with: range)
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let back = NSRange(location: range.location, length: replacement.utf16.count)
                model.registerText(range: back, replacement: old)
                model.text = (model.text as NSString).replacingCharacters(in: back, with: old)
                model.selection = NSRange(location: range.location, length: old.utf16.count)
            }
        }
    }

    func registerSelection(select: NSRange?, reverse: NSRange?) {
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                if let select { model.selection = select }
                model.registerSelection(select: reverse, reverse: select)
            }
        }
    }
}
