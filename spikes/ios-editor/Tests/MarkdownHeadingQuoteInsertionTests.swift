import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class MarkdownHeadingQuoteInsertionTests: XCTestCase {
    private let cases: [(MarkdownInsertionCommand, String, String)] = [
        (.heading1, "# ", "heading"), (.heading2, "## ", "heading"),
        (.heading3, "### ", "heading"), (.blockquote, "> ", "text")
    ]

    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    private func fullRange(_ source: String) -> NSRange { NSRange(location: 0, length: source.utf16.count) }

    func testHeadingsPrefixOnlyNonblankSelectedRowsAndPreserveOutsideBytes() throws {
        let prefix = "\u{FEFF}before\r\n"
        let body = "Cafe\u{301} 😀\r\n \t\r# literal\n\nlast"
        let suffix = "\rafter\n"
        for (command, marker, _) in cases where command != .blockquote {
            let range = NSRange(location: prefix.utf16.count, length: body.utf16.count)
            let expected = marker + "Cafe\u{301} 😀\r\n \t\r" + marker + "# literal\n\n" + marker + "last"
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: prefix + body + suffix, selection: range))
            bytesEqual(plan.replacement, expected)
            bytesEqual(apply(plan), prefix + expected + suffix)
            XCTAssertEqual(plan.range, range)
            XCTAssertEqual(plan.selectionAfter, NSRange(location: prefix.utf16.count, length: expected.utf16.count))
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), expected)
        }
    }

    func testQuotePrefixesSelectedEdgeAndInteriorBlankRowsWithoutPhantomTrailingRow() throws {
        let body = "\r\n \t\rCafe\u{301} 😀\n\n> literal\r\n\t\r"
        let prefix = "\u{FEFF}outside\n"
        let suffix = "after\n"
        let expected = "> \r\n>  \t\r> Cafe\u{301} 😀\n> \n> > literal\r\n> \t\r"
        let range = NSRange(location: prefix.utf16.count, length: body.utf16.count)
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .blockquote, source: prefix + body + suffix, selection: range))
        bytesEqual(plan.replacement, expected)
        bytesEqual(apply(plan), prefix + expected + suffix)
        XCTAssertEqual(plan.selectionAfter, NSRange(location: prefix.utf16.count, length: expected.utf16.count))
        XCTAssertTrue(plan.replacement.hasSuffix("> \t\r"))
    }

    func testLeadingBOMStaysFirstAndOutsideResultSelection() throws {
        let source = "\u{FEFF}Cafe\u{301} 😀\r\n\rnext\n"
        for (command, marker, _) in cases {
            let blankMarker = command == .blockquote ? marker : ""
            let expected = "\u{FEFF}" + marker + "Cafe\u{301} 😀\r\n" + blankMarker + "\r" + marker + "next\n"
            for range in [fullRange(source), NSRange(location: 1, length: source.utf16.count - 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
                bytesEqual(apply(plan), expected)
                XCTAssertEqual(plan.range, range)
                XCTAssertEqual(plan.selectionAfter, NSRange(location: 1, length: expected.utf16.count - 1))
            }
        }
    }

    func testNonblankRowStartCaretInsertsOnlyMarkerAfterBOMOrPhysicalEnding() throws {
        for (command, marker, _) in cases {
            for (source, location) in [("Cafe\u{301} 😀\r\n", 0), ("before\r\n  literal", "before\r\n".utf16.count), ("\u{FEFF}literal", 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
                bytesEqual(plan.replacement, marker)
                bytesEqual(apply(plan), (source as NSString).substring(to: location) + marker + (source as NSString).substring(from: location))
                XCTAssertEqual(plan.selectionAfter, NSRange(location: location + marker.utf16.count, length: 0))
            }
        }
    }

    func testBlankRowCaretSelectsExactPlaceholderWithoutTrimmingOrAddingEnding() throws {
        for (command, marker, placeholder) in cases {
            for (source, location) in [("", 0), (" \t\r\nnext", 0), ("before\n", "before\n".utf16.count), ("\u{FEFF}", 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
                bytesEqual(plan.replacement, marker + placeholder)
                bytesEqual(apply(plan), (source as NSString).substring(to: location) + marker + placeholder + (source as NSString).substring(from: location))
                XCTAssertEqual(plan.selectionAfter, NSRange(location: location + marker.utf16.count, length: placeholder.utf16.count))
                bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), placeholder)
            }
        }
    }

    func testWholePhysicalRowSelectionMayEndBeforeOrAfterEndingOrAtEOF() {
        let source = "before\r\none\r\ntwo\nafter"
        let start = "before\r\n".utf16.count
        for (command, _, _) in cases {
            for body in ["one", "one\r\n", "one\r\ntwo", "one\r\ntwo\n", "one\r\ntwo\nafter"] {
                XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: start, length: body.utf16.count)))
            }
        }
    }

    func testPartialRowsInvalidUTF16CRLFInteriorsAndCaretBeforeBOMAreRefused() {
        let source = "\u{FEFF}😀one\r\ntwo\n"
        for (command, _, _) in cases {
            for range in [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0),
                          NSRange(location: 1, length: 1), NSRange(location: 1, length: 3),
                          NSRange(location: 3, length: 3), NSRange(location: 7, length: 0),
                          NSRange(location: 1, length: 6), NSRange(location: 8, length: 1),
                          NSRange(location: 3, length: 0), NSRange(location: NSNotFound, length: 0),
                          NSRange(location: -1, length: 0), NSRange(location: 0, length: Int.max)] {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: range), "\(command): \(range)")
            }
        }
    }

    func testEntirelyBlankSelectedBatchesAreExplicitlyRefused() {
        for source in [" ", "\t\r\n \n", "\u{A0}\r", "\u{FEFF}", "\u{FEFF} \r\n\t\n"] {
            for (command, _, _) in cases {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: fullRange(source)))
            }
        }
    }

    func testCaretMustBePhysicalRowStartRatherThanEndOfExistingNonblankRow() {
        for (source, location) in [("line", 1), ("line", 4), ("\u{FEFF}line", 0), ("a\r\nb", 2), ("a\rb", 3)] {
            for (command, _, _) in cases {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
            }
        }
    }

    func testPhysicalRowLimitIncludesSelectedBlanksAndExcludesPhantomTerminalRow() throws {
        let limit = MarkdownInsertionPlan.maximumPrefixRows
        for (command, marker, _) in cases {
            for source in [String(repeating: "x\r\n", count: limit), "x\n" + String(repeating: "\n", count: limit - 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: fullRange(source)))
                XCTAssertTrue(plan.replacement.hasSuffix("\n"))
                if command == .blockquote { XCTAssertEqual(plan.replacement.utf8.count, source.utf8.count + limit * marker.utf8.count) }
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source + "\n", selection: fullRange(source + "\n")))
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source + "x", selection: fullRange(source + "x")))
            }
        }
    }

    func testSelectionSourceAndGrowthLimitsCountUTF8Bytes() throws {
        let selected = String(repeating: "😀", count: MarkdownInsertionPlan.maximumSelectionBytes / 4)
        let over = selected + "x"
        for (command, marker, placeholder) in cases {
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: selected, selection: fullRange(selected)))
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: over, selection: fullRange(over)))
            let boundary = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - marker.utf8.count)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: boundary, selection: .init(location: 0, length: 0)))
            XCTAssertEqual(apply(plan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: boundary + "x", selection: .init(location: 0, length: 0)))
            let oversized = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes + 1)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: oversized, selection: .init(location: 0, length: 0)))
            let prefix = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - marker.utf8.count - 2) + "\n"
            let source = prefix + "y"
            let selectedPlan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source,
                selection: .init(location: prefix.utf16.count, length: 1)))
            XCTAssertEqual(apply(selectedPlan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source + "z",
                selection: .init(location: prefix.utf16.count, length: 2)))
            let blankBoundary = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - marker.utf8.count - placeholder.utf8.count - 1) + "\n"
            let blankPlan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: blankBoundary,
                selection: .init(location: blankBoundary.utf16.count, length: 0)))
            XCTAssertEqual(apply(blankPlan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: blankBoundary + " ",
                selection: .init(location: blankBoundary.utf16.count, length: 0)))
        }
    }

    func testLiteralContextAndStaleSnapshotRemainExactBytesAndRange() throws {
        let source = "```\r\n# Café 😀\n> <script>inert()</script>\r```\n"
        let range = fullRange(source)
        for (command, marker, _) in cases {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            bytesEqual(plan.replacement, marker + "```\r\n" + marker + "# Café 😀\n" + marker + "> <script>inert()</script>\r" + marker + "```\n")
            bytesEqual(plan.source, source)
            XCTAssertTrue(plan.matches(source: source, selection: range))
            XCTAssertFalse(plan.matches(source: source.replacingOccurrences(of: "Café", with: "Cafe\u{301}"), selection: range))
            XCTAssertFalse(plan.matches(source: source.replacingOccurrences(of: "\r\n", with: "\n"), selection: range))
            XCTAssertFalse(plan.matches(source: source + "x", selection: range))
            XCTAssertFalse(plan.matches(source: source, selection: .init(location: 0, length: range.length - 1)))
        }
    }
}
