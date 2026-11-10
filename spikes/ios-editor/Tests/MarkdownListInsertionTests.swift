import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class MarkdownListInsertionTests: XCTestCase {
    private let commands: [MarkdownInsertionCommand] = [.bulletedList, .numberedList, .taskList]

    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    private func fullRange(_ source: String) -> NSRange { NSRange(location: 0, length: source.utf16.count) }

    func testSelectedPhysicalRowsPreserveMixedEndingsBlankRowsAndLiteralMarkers() throws {
        let prefix = "\u{FEFF}before\r\n"
        let body = "Cafe\u{301} 😀\r\n \t\rnext\n\n- literal\r\nlast"
        let suffix = "\rafter\n"
        for (command, expected) in [
            (MarkdownInsertionCommand.bulletedList, "- Cafe\u{301} 😀\r\n \t\r- next\n\n- - literal\r\n- last"),
            (.numberedList, "1. Cafe\u{301} 😀\r\n \t\r2. next\n\n3. - literal\r\n4. last"),
            (.taskList, "- [ ] Cafe\u{301} 😀\r\n \t\r- [ ] next\n\n- [ ] - literal\r\n- [ ] last")
        ] {
            let range = NSRange(location: prefix.utf16.count, length: body.utf16.count)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: prefix + body + suffix, selection: range))
            bytesEqual(plan.replacement, expected)
            bytesEqual(apply(plan), prefix + expected + suffix)
            XCTAssertEqual(plan.range, range)
            XCTAssertEqual(plan.selectionAfter, NSRange(location: prefix.utf16.count, length: expected.utf16.count))
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), expected)
        }
    }

    func testWholeLineBoundaryRulesAcceptEndBeforeOrAfterEndingAndRefusePartialLines() throws {
        let source = "before\r\none\r\ntwo\nafter"
        let start = "before\r\n".utf16.count
        for length in ["one".utf16.count, "one\r\n".utf16.count, "one\r\ntwo".utf16.count] {
            for command in commands {
                XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: start, length: length)))
            }
        }
        for range in [NSRange(location: start + 1, length: 2), NSRange(location: start, length: 1),
                      NSRange(location: start, length: 2), NSRange(location: start, length: 4),
                      NSRange(location: 1, length: source.utf16.count - 1)] {
            for command in commands {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            }
        }
    }

    func testLeadingBOMPrecedesMarkerAndIsExcludedFromTransformedSelection() throws {
        let source = "\u{FEFF}Cafe\u{301} 😀\r\nnext\n"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bulletedList, source: source, selection: fullRange(source)))
        let expected = "\u{FEFF}- Cafe\u{301} 😀\r\n- next\n"
        bytesEqual(plan.replacement, expected)
        bytesEqual(apply(plan), expected)
        XCTAssertEqual(plan.selectionAfter, NSRange(location: 1, length: expected.utf16.count - 1))
        bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "- Cafe\u{301} 😀\r\n- next\n")
        let afterBOM = try XCTUnwrap(MarkdownInsertionPlan.make(command: .taskList, source: source,
            selection: NSRange(location: 1, length: source.utf16.count - 1)))
        bytesEqual(apply(afterBOM), "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n- [ ] next\n")
        XCTAssertEqual(afterBOM.selectionAfter.location, 1)
    }

    func testBlankRowsAndBOMOnlySelectionsAreNoOpsAndRefused() {
        for source in [" ", "\t\r\n \n", "\u{A0}\r", "\u{FEFF}", "\u{FEFF} \r\n\t\n"] {
            for command in commands {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: fullRange(source)))
            }
        }
        let source = "\u{FEFF}\ncontent"
        let plan = MarkdownInsertionPlan.make(command: .bulletedList, source: source, selection: fullRange(source))
        XCTAssertEqual(plan?.replacement, "\u{FEFF}\n- content")
    }

    func testEmptyCaretOnExistingNonblankRowsInsertsOnlyMarkerAndLeavesCaretAfterIt() throws {
        for (command, marker) in [(MarkdownInsertionCommand.bulletedList, "- "), (.numberedList, "1. "), (.taskList, "- [ ] ")] {
            for (source, location) in [("Cafe\u{301} 😀\r\n", 0), ("before\r\n  literal", "before\r\n".utf16.count), ("\u{FEFF}literal", 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
                bytesEqual(plan.replacement, marker)
                XCTAssertEqual(plan.selectionAfter, NSRange(location: location + marker.utf16.count, length: 0))
                let prefix = (source as NSString).substring(to: location)
                let suffix = (source as NSString).substring(from: location)
                bytesEqual(apply(plan), prefix + marker + suffix)
            }
        }
    }

    func testEmptyOrWhitespaceRowGetsSelectedItemWithoutAddingSeparatorsOrTrimming() throws {
        for (command, marker) in [(MarkdownInsertionCommand.bulletedList, "- "), (.numberedList, "1. "), (.taskList, "- [ ] ")] {
            for (source, location) in [("", 0), (" \t\r\nnext", 0), ("before\n", "before\n".utf16.count), ("\u{FEFF}", 1)] {
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
                bytesEqual(plan.replacement, marker + "item")
                XCTAssertEqual(plan.selectionAfter, NSRange(location: location + marker.utf16.count, length: 4))
                bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "item")
                bytesEqual(apply(plan), (source as NSString).substring(to: location) + marker + "item" + (source as NSString).substring(from: location))
            }
        }
    }

    func testEmptyCaretMustBeAtPhysicalStartAndCannotPrecedeLeadingBOM() {
        for (source, location) in [("line", 1), ("line", 4), ("\u{FEFF}line", 0), ("a\r\nb", 2)] {
            for command in commands {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source,
                    selection: NSRange(location: location, length: 0)))
            }
        }
    }

    func testNumberingCountsOnlyNonblankRowsThroughTwoDigitsAndRetainsTrailingEnding() throws {
        let rows = (1...12).map { "row\($0)" }
        let source = rows.prefix(5).joined(separator: "\n") + "\n \t\n" + rows.suffix(7).joined(separator: "\n") + "\r\n"
        let expected = (1...5).map { "\($0). row\($0)" }.joined(separator: "\n") + "\n \t\n"
            + (6...12).map { "\($0). row\($0)" }.joined(separator: "\n") + "\r\n"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .numberedList, source: source, selection: fullRange(source)))
        bytesEqual(plan.replacement, expected)
        XCTAssertTrue(plan.replacement.hasSuffix("12. row12\r\n"))
        XCTAssertEqual(plan.selectionAfter.length, expected.utf16.count)
    }

    func testPhysicalRowLimitCountsBlankRowsButNotTerminalEmptyRow() throws {
        let maximum = String(repeating: "x\r\n", count: MarkdownInsertionPlan.maximumListLines)
        for command in commands {
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: maximum, selection: fullRange(maximum)))
            let over = maximum + "x"
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: over, selection: fullRange(over)))
            let blankBoundary = "x\n" + String(repeating: "\n", count: MarkdownInsertionPlan.maximumListLines - 1)
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: blankBoundary, selection: fullRange(blankBoundary)))
            let blankOver = blankBoundary + "\n"
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: blankOver, selection: fullRange(blankOver)))
        }
    }

    func testListSelectionSourceAndOutputByteLimitsUseBytesNotCharacters() throws {
        let selected = String(repeating: "😀", count: MarkdownInsertionPlan.maximumSelectionBytes / 4)
        let oversized = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes + 1)
        for (command, marker) in [(MarkdownInsertionCommand.bulletedList, "- "), (.numberedList, "1. "), (.taskList, "- [ ] ")] {
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: selected, selection: fullRange(selected)))
            let over = selected + "x"
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: over, selection: fullRange(over)))
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: oversized, selection: NSRange(location: 0, length: 0)))
            let boundary = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - marker.utf8.count)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: boundary, selection: NSRange(location: 0, length: 0)))
            XCTAssertEqual(apply(plan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: boundary + "x", selection: NSRange(location: 0, length: 0)))
        }
        let prefix = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - 8) + "\n"
        let source = prefix + "y"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .taskList, source: source,
            selection: NSRange(location: prefix.utf16.count, length: 1)))
        XCTAssertEqual(apply(plan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
    }

    func testLiteralScriptLookingSourceAndStaleBytesRemainUninterpreted() throws {
        let source = "<script>inert()</script>\n- [x] Café\r\n1. existing\n"
        for command in commands {
            let range = fullRange(source)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            XCTAssertTrue(plan.replacement.contains("<script>inert()</script>"))
            XCTAssertTrue(plan.replacement.contains("- [x] Café\r\n"))
            XCTAssertTrue(plan.replacement.contains("1. existing\n"))
            bytesEqual(plan.source, source)
            XCTAssertTrue(plan.matches(source: source, selection: range))
            XCTAssertFalse(plan.matches(source: source.replacingOccurrences(of: "Café", with: "Cafe\u{301}"), selection: range))
            XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 0, length: range.length - 1)))
        }
    }
}
