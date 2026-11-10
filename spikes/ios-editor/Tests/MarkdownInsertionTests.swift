import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class MarkdownInsertionTests: XCTestCase {
    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    func testTitlesAndEmptySelectionPlaceholdersSelectBodyInsideMarkers() throws {
        XCTAssertEqual(MarkdownInsertionCommand.allCases.map(\.title), ["Bold", "Italic", "Inline code"])
        for (command, replacement, offset, body) in [
            (MarkdownInsertionCommand.bold, "**text**", 2, "text"),
            (.italic, "*text*", 1, "text"),
            (.inlineCode, "`code`", 1, "code")
        ] {
            let source = "😀 before\r\nafter"
            let selection = NSRange(location: ("😀 before\r\n" as NSString).length, length: 0)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: selection))
            bytesEqual(plan.source, source)
            XCTAssertEqual(plan.range, selection)
            XCTAssertEqual(plan.replacement, replacement)
            XCTAssertEqual(plan.selectionAfter, NSRange(location: selection.location + offset, length: body.utf16.count))
            let result = apply(plan)
            bytesEqual(result, "😀 before\r\n" + replacement + "after")
            bytesEqual((result as NSString).substring(with: plan.selectionAfter), body)
            let empty = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: "", selection: .init(location: 0, length: 0)))
            XCTAssertEqual(empty.replacement, replacement)
            XCTAssertEqual(empty.selectionAfter, NSRange(location: offset, length: body.utf16.count))
        }
    }

    func testLiteralWrappingPreservesBOMNFDAndUntouchedPhysicalEndings() throws {
        let prefix = "\u{FEFF}first\r\n"
        let body = "Cafe\u{301} 😀 **literal**"
        let suffix = "\rlast\n"
        let source = prefix + body + suffix
        let range = NSRange(location: prefix.utf16.count, length: body.utf16.count)
        for (command, marker) in [(MarkdownInsertionCommand.bold, "**"), (.italic, "*")] {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            bytesEqual(plan.replacement, marker + body + marker)
            let result = apply(plan)
            bytesEqual(result, prefix + marker + body + marker + suffix)
            bytesEqual((result as NSString).substring(with: plan.selectionAfter), body)
        }
        let alreadyMarked = "**already**"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: alreadyMarked,
                                                          selection: NSRange(location: 0, length: alreadyMarked.utf16.count)))
        XCTAssertEqual(plan.replacement, "****already****")
    }

    func testSelectedCombiningScalarIsPreservedWithoutRoundingToGrapheme() throws {
        let source = "e\u{301}nd"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .italic, source: source,
                                                          selection: NSRange(location: 1, length: 1)))
        bytesEqual(plan.replacement, "*\u{301}*")
        bytesEqual(apply(plan), "e*\u{301}*nd")
        XCTAssertEqual(plan.selectionAfter, NSRange(location: 2, length: 1))
    }

    func testInlineCodeDelimiterAndSymmetricPaddingPreserveSelectedBody() throws {
        for (body, expected, offset) in [
            ("plain", "`plain`", 1),
            ("a``b`c", "```a``b`c```", 3),
            ("`edge", "`` `edge ``", 3),
            ("edge`", "`` edge` ``", 3),
            ("`", "`` ` ``", 3),
            (" a ", "`  a  `", 2),
            (" a", "` a`", 1),
            ("a ", "`a `", 1),
            (" \tword ", "`  \tword  `", 2),
            ("Cafe\u{301} 😀", "`Cafe\u{301} 😀`", 1)
        ] {
            let prefix = "\u{FEFF}before\r\n"
            let suffix = "\rafter\n"
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .inlineCode, source: prefix + body + suffix,
                selection: NSRange(location: prefix.utf16.count, length: body.utf16.count)), body)
            bytesEqual(plan.replacement, expected)
            XCTAssertEqual(plan.selectionAfter.location, prefix.utf16.count + offset)
            bytesEqual(apply(plan), prefix + expected + suffix)
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
        }
    }

    func testInlineCodeRejectsCRLFAndWhitespaceOnlySelectedBodies() {
        for source in ["a\rb", "a\nb", "a\r\nb", " ", "   ", "\t", " \t ", "\u{A0}", "\u{2028}"] {
            XCTAssertNil(MarkdownInsertionPlan.make(command: .inlineCode, source: source,
                selection: NSRange(location: 0, length: source.utf16.count)), String(reflecting: source))
        }
        // Bold/italic remain literal wrappers even when their body is multiline.
        let source = "a\r\nb\rc\n"
        for command in [MarkdownInsertionCommand.bold, .italic] {
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: source,
                selection: NSRange(location: 0, length: source.utf16.count)))
        }
    }

    func testInvalidRangesAreRefusedWithoutOverflowOrBoundaryRounding() {
        let source = "😀a\r\nb"
        for range in [
            NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
            NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: NSNotFound),
            NSRange(location: Int.max, length: Int.max), NSRange(location: 2, length: Int.max),
            NSRange(location: source.utf16.count + 1, length: 0), NSRange(location: 1, length: 0),
            NSRange(location: 0, length: 1), NSRange(location: 4, length: 0),
            NSRange(location: 3, length: 1), NSRange(location: 4, length: 1)
        ] {
            for command in MarkdownInsertionCommand.allCases {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            }
        }
        XCTAssertNotNil(MarkdownInsertionPlan.make(command: .bold, source: source,
            selection: NSRange(location: 3, length: 2))) // The complete CRLF remains valid source.
    }

    func testSelectionByteBudgetCountsMultibyteTextAndBoundsBacktickDelimiter() throws {
        let boundary = String(repeating: "😀", count: MarkdownInsertionPlan.maximumSelectionBytes / 4)
        XCTAssertNotNil(MarkdownInsertionPlan.make(command: .bold, source: boundary,
            selection: NSRange(location: 0, length: boundary.utf16.count)))
        let over = boundary + "x"
        XCTAssertNil(MarkdownInsertionPlan.make(command: .bold, source: over,
            selection: NSRange(location: 0, length: over.utf16.count)))
        let ticks = String(repeating: "`", count: MarkdownInsertionPlan.maximumSelectionBytes)
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .inlineCode, source: ticks,
            selection: NSRange(location: 0, length: ticks.utf16.count)))
        XCTAssertEqual(plan.replacement.utf8.count, 3 * ticks.utf8.count + 4)
        XCTAssertEqual(plan.selectionAfter, NSRange(location: ticks.utf16.count + 2, length: ticks.utf16.count))
        let tooManyTicks = ticks + "`"
        XCTAssertNil(MarkdownInsertionPlan.make(command: .inlineCode, source: tooManyTicks,
            selection: NSRange(location: 0, length: tooManyTicks.utf16.count)))
    }

    func testSourceAndResultByteLimitsRefuseOversizedOutputBeforeReplacement() throws {
        let limit = MarkdownInsertionPlan.maximumSourceBytes
        let boundary = String(repeating: "x", count: limit - 8)
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: boundary, selection: .init(location: 0, length: 0)))
        XCTAssertEqual(apply(plan).utf8.count, limit)
        XCTAssertNil(MarkdownInsertionPlan.make(command: .bold, source: boundary + "x", selection: .init(location: 0, length: 0)))
        let full = String(repeating: "x", count: limit)
        XCTAssertNil(MarkdownInsertionPlan.make(command: .italic, source: full, selection: .init(location: 0, length: 1)))
        XCTAssertNil(MarkdownInsertionPlan.make(command: .bold, source: full + "x", selection: .init(location: 0, length: 1)))
        let multibyte = String(repeating: "😀", count: limit / 4)
        XCTAssertNil(MarkdownInsertionPlan.make(command: .bold, source: multibyte, selection: .init(location: 0, length: 2)))
    }

    func testStaleGuardRequiresExactOriginalBytesAndSelection() throws {
        let source = "Café 😀\r\n"
        let range = NSRange(location: 0, length: 4)
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: source, selection: range))
        XCTAssertTrue(plan.matches(source: source, selection: range))
        XCTAssertFalse(plan.matches(source: "Cafe\u{301} 😀\r\n", selection: range))
        XCTAssertFalse(plan.matches(source: "Café 😀\n", selection: range))
        XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 1, length: 3)))
        XCTAssertFalse(plan.matches(source: source + "x", selection: range))
        bytesEqual(plan.source, source)
    }

    func testMalformedMarkdownAndScriptShapedSourceStayLiteralInput() throws {
        let body = "<script>inert()</script> [broken]( ```unterminated"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .inlineCode, source: body,
            selection: NSRange(location: 0, length: body.utf16.count)))
        bytesEqual(plan.source, body)
        bytesEqual(plan.replacement, "````" + body + "````")
        bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
    }
}
