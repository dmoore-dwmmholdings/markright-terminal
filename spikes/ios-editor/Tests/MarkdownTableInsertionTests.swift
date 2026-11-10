import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class MarkdownTableInsertionTests: XCTestCase {
    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    private func fullRange(_ source: String) -> NSRange { NSRange(location: 0, length: source.utf16.count) }

    func testEmptyRowStarterUsesFirstDocumentEndingAndSelectsValueOne() throws {
        for eol in ["\n", "\r", "\r\n"] {
            let prefix = "\u{FEFF}before" + eol
            let source = prefix + eol + "after\n"
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .table, source: source,
                selection: NSRange(location: prefix.utf16.count, length: 0)))
            let expected = "| Column 1 | Column 2 |" + eol + "| --- | --- |" + eol + "| Value 1 | Value 2 |"
            bytesEqual(plan.replacement, expected)
            bytesEqual(apply(plan), prefix + expected + eol + "after\n")
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "Value 1")
            XCTAssertEqual(plan.selectionAfter.length, 7)
        }
        let empty = try XCTUnwrap(MarkdownTableInsertion.make(source: "", selection: NSRange(location: 0, length: 0)))
        XCTAssertEqual(empty.replacement, "| Column 1 | Column 2 |\n| --- | --- |\n| Value 1 | Value 2 |")
        XCTAssertFalse(empty.replacement.hasSuffix("\n"))
    }

    func testStarterRequiresTrulyEmptyPhysicalRowAndRespectsLeadingBOM() throws {
        for (source, location) in [("text", 0), ("text", 4), (" \t\n", 0), ("\u{FEFF}", 0), ("a\r\nb", 2)] {
            XCTAssertNil(MarkdownTableInsertion.make(source: source, selection: NSRange(location: location, length: 0)))
        }
        for (source, location) in [("\u{FEFF}", 1), ("before\r\n", "before\r\n".utf16.count), ("\r\n", 0)] {
            let plan = try XCTUnwrap(MarkdownTableInsertion.make(source: source, selection: NSRange(location: location, length: 0)))
            let prefix = (source as NSString).substring(to: location)
            let suffix = (source as NSString).substring(from: location)
            bytesEqual(apply(plan), prefix + plan.replacement + suffix)
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "Value 1")
        }
    }

    func testTSVPreservesBOMNFDUnicodeMixedRowsAndHeaderEndingForDelimiter() throws {
        let prefix = "outside\n"
        let body = "H1\tH2\r\nCafe\u{301} 😀\t value \rthird\tlast\n"
        let suffix = "after\r"
        let plan = try XCTUnwrap(MarkdownTableInsertion.make(source: prefix + body + suffix,
            selection: NSRange(location: prefix.utf16.count, length: body.utf16.count)))
        let expected = "| H1 | H2 |\r\n| --- | --- |\r\n| Cafe\u{301} 😀 |  value  |\r| third | last |\n"
        bytesEqual(plan.replacement, expected)
        bytesEqual(apply(plan), prefix + expected + suffix)
        bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "Cafe\u{301} 😀")
        for eol in ["\r", "\n", "\r\n"] {
            let source = "\u{FEFF}A\tB" + eol + "😀\te\u{301}"
            let bom = try XCTUnwrap(MarkdownTableInsertion.make(source: source, selection: fullRange(source)))
            bytesEqual(bom.replacement, "\u{FEFF}| A | B |" + eol + "| --- | --- |" + eol + "| 😀 | e\u{301} |")
            XCTAssertEqual((apply(bom) as NSString).substring(with: bom.selectionAfter), "😀")
            XCTAssertEqual(bom.selectionAfter.length, 2)
            let afterBOM = try XCTUnwrap(MarkdownTableInsertion.make(source: source,
                selection: NSRange(location: 1, length: source.utf16.count - 1)))
            bytesEqual(apply(afterBOM), bom.replacement)
        }
    }

    func testOriginalLastEndingIsPreservedWithoutPhantomRowOrAddedEnding() throws {
        for ending in ["", "\r", "\n", "\r\n"] {
            let source = "a\tb\r\nx\ty" + ending
            let plan = try XCTUnwrap(MarkdownTableInsertion.make(source: source, selection: fullRange(source)))
            bytesEqual(plan.replacement, "| a | b |\r\n| --- | --- |\r\n| x | y |" + ending)
        }
    }

    func testEmptyCellsAndEmptyFirstDataCellAreRetainedWithoutTrimming() throws {
        let source = "\t Header \t\n\tvalue\t\nlast\t\tend"
        let plan = try XCTUnwrap(MarkdownTableInsertion.make(source: source, selection: fullRange(source)))
        bytesEqual(plan.replacement, "|  |  Header  |  |\n| --- | --- | --- |\n|  | value |  |\n| last |  | end |")
        XCTAssertEqual(plan.selectionAfter.length, 0)
        XCTAssertEqual(plan.selectionAfter.location, "|  |  Header  |  |\n| --- | --- | --- |\n| ".utf16.count)
        XCTAssertTrue(SourceSelection.isValid(plan.selectionAfter, in: apply(plan)))
    }

    func testRectangularMinimumAndMaximumDimensionsAreEnforced() throws {
        for source in ["one", "a\tb", "a\nb", "a\tb\nc\td\te", "a\tb\n", "a\tb\n\n"] {
            XCTAssertNil(MarkdownTableInsertion.make(source: source, selection: fullRange(source)), String(reflecting: source))
        }
        let row = (1...MarkdownTableInsertion.maxColumns).map { "C\($0)" }.joined(separator: "\t")
        let maximum = Array(repeating: row, count: MarkdownTableInsertion.maxRows).joined(separator: "\r\n") + "\r\n"
        XCTAssertNotNil(MarkdownTableInsertion.make(source: maximum, selection: fullRange(maximum)))
        let tooManyRows = maximum + row
        XCTAssertNil(MarkdownTableInsertion.make(source: tooManyRows, selection: fullRange(tooManyRows)))
        let wide = row + "\textra\n" + row + "\textra"
        XCTAssertNil(MarkdownTableInsertion.make(source: wide, selection: fullRange(wide)))
        let minimum = "a\tb\nc\td"
        XCTAssertNotNil(MarkdownTableInsertion.make(source: minimum, selection: fullRange(minimum)))
    }

    func testUnsupportedCellsAndAllWhitespaceGridAreRefusedWithoutEscaping() {
        for cell in ["a|b", "a\\b", "a\u{0}b", "a\u{7F}b", "a\u{B}b"] {
            let source = "header\tother\n" + cell + "\tvalue"
            XCTAssertNil(MarkdownTableInsertion.make(source: source, selection: fullRange(source)), String(reflecting: cell))
        }
        for source in ["\t\n\t", " \t\u{A0}\r\n\t ", "\u{FEFF}\t\n\t"] {
            XCTAssertNil(MarkdownTableInsertion.make(source: source, selection: fullRange(source)))
        }
        let someEmpty = "\t\n\tvalue"
        XCTAssertNotNil(MarkdownTableInsertion.make(source: someEmpty, selection: fullRange(someEmpty)))
    }

    func testSelectionsRequireWholePhysicalRowsAndStrictUTF16Boundaries() {
        let body = "a\tb\r\nx\t😀"
        let source = "before\n" + body + "\r\nafter"
        let start = "before\n".utf16.count
        XCTAssertNotNil(MarkdownTableInsertion.make(source: source, selection: NSRange(location: start, length: body.utf16.count)))
        XCTAssertNotNil(MarkdownTableInsertion.make(source: source, selection: NSRange(location: start, length: body.utf16.count + 2)))
        for range in [NSRange(location: start + 1, length: body.utf16.count - 1),
                      NSRange(location: start, length: body.utf16.count - 1),
                      NSRange(location: start, length: body.utf16.count + 1),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 0),
                      NSRange(location: 0, length: Int.max), NSRange(location: Int.max, length: Int.max)] {
            XCTAssertNil(MarkdownTableInsertion.make(source: source, selection: range))
        }
    }

    func testSelectionSourceAndResultByteBoundsAreEnforcedByDirectHelper() throws {
        let fixed = "a\tb\n\t" // Five ASCII bytes, followed by the final cell.
        let cell = String(repeating: "😀", count: (MarkdownInsertionPlan.maximumSelectionBytes - fixed.utf8.count) / 4)
        let fill = String(repeating: "x", count: MarkdownInsertionPlan.maximumSelectionBytes - fixed.utf8.count - cell.utf8.count)
        let boundary = fixed + cell + fill
        XCTAssertEqual(boundary.utf8.count, MarkdownInsertionPlan.maximumSelectionBytes)
        XCTAssertNotNil(MarkdownTableInsertion.make(source: boundary, selection: fullRange(boundary)))
        let over = boundary + "x"
        XCTAssertNil(MarkdownTableInsertion.make(source: over, selection: fullRange(over)))
        let oversized = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes + 1)
        XCTAssertNil(MarkdownTableInsertion.make(source: oversized, selection: NSRange(location: 0, length: 0)))

        let grid = "a\tb\nx\ty"
        let sample = try XCTUnwrap(MarkdownTableInsertion.make(source: grid, selection: fullRange(grid)))
        let overhead = sample.replacement.utf8.count - grid.utf8.count
        let prefix = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - overhead - grid.utf8.count - 1) + "\n"
        let source = prefix + grid
        let plan = try XCTUnwrap(MarkdownTableInsertion.make(source: source,
            selection: NSRange(location: prefix.utf16.count, length: grid.utf16.count)))
        XCTAssertEqual(apply(plan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
        let tooLarge = "x" + source
        XCTAssertNil(MarkdownTableInsertion.make(source: tooLarge,
            selection: NSRange(location: prefix.utf16.count + 1, length: grid.utf16.count)))
    }

    func testScriptShapedAndMalformedMarkdownCellsRemainLiteralAndStaleGuardIsExact() throws {
        let source = "<script>inert()</script>\t[broken](\nCafé\t````"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .table, source: source, selection: fullRange(source)))
        bytesEqual(plan.replacement, "| <script>inert()</script> | [broken]( |\n| --- | --- |\n| Café | ```` |")
        bytesEqual(plan.source, source)
        XCTAssertTrue(plan.matches(source: source, selection: fullRange(source)))
        XCTAssertFalse(plan.matches(source: source.replacingOccurrences(of: "Café", with: "Cafe\u{301}"), selection: fullRange(source)))
        XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 0, length: source.utf16.count - 1)))
    }
}
