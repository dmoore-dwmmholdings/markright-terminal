import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class MarkdownStructureInsertionTests: XCTestCase {
    private let commands: [MarkdownInsertionCommand] = [.link, .imageReference, .codeBlock]

    private func apply(_ plan: MarkdownInsertionPlan) -> String {
        (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    func testLinkAndImagePlaceholdersSelectDestinationInsteadOfLabel() throws {
        for (command, expected) in [
            (MarkdownInsertionCommand.link, "[link text](destination)"),
            (.imageReference, "![alt text](destination)")
        ] {
            for source in ["", "\u{FEFF}😀\r\nafter"] {
                let selection = NSRange(location: source.isEmpty ? 0 : "\u{FEFF}😀\r\n".utf16.count, length: 0)
                let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: selection))
                bytesEqual(plan.replacement, expected)
                let result = apply(plan)
                bytesEqual((result as NSString).substring(with: plan.selectionAfter), "destination")
                XCTAssertEqual(plan.selectionAfter.length, 11)
                bytesEqual(plan.source, source)
            }
        }
    }

    func testSelectedLabelBytesAndUntouchedNeighborsAreLiteral() throws {
        let prefix = "\u{FEFF}before\r\n"
        let body = "Cafe\u{301} 😀 **literal** <script>inert()</script> (text)"
        let suffix = "\rafter\n"
        for command in [MarkdownInsertionCommand.link, .imageReference] {
            let marker = command == .link ? "[" : "!["
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: prefix + body + suffix,
                selection: NSRange(location: prefix.utf16.count, length: body.utf16.count)))
            bytesEqual(plan.replacement, marker + body + "](destination)")
            bytesEqual(apply(plan), prefix + marker + body + "](destination)" + suffix)
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "destination")
        }
    }

    func testUnsupportedLabelsAreRefusedWithoutParsingOrEscaping() {
        for body in ["[label", "label]", "a\\b", "a\nb", "a\rb", "a\r\nb", "a\tb", "a\u{0}b", "a\u{7F}b", " ", "\u{A0}", " \t "] {
            for command in [MarkdownInsertionCommand.link, .imageReference] {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: body,
                    selection: NSRange(location: 0, length: body.utf16.count)), String(reflecting: body))
            }
        }
    }

    func testCodeBlockEmptyCaretPositionsInsertOnlyNeededPhysicalSeparators() throws {
        for (source, location, expected, bodyOffset) in [
            ("", 0, "```\ncode\n```", 4),
            ("beforeafter", 6, "\n```\ncode\n```\n", 5),
            ("before\nafter", 7, "```\ncode\n```\n", 4),
            ("before\nafter", 6, "\n```\ncode\n```", 5),
            ("before", 6, "\n```\ncode\n```", 5)
        ] {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: source,
                selection: NSRange(location: location, length: 0)))
            bytesEqual(plan.replacement, expected)
            XCTAssertEqual(plan.selectionAfter, NSRange(location: location + bodyOffset, length: 4))
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), "code")
        }
        let middle = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: "beforeafter",
            selection: NSRange(location: 6, length: 0)))
        bytesEqual(apply(middle), "before\n```\ncode\n```\nafter")
    }

    func testCodeBlockUsesFirstPhysicalDocumentEndingAndPreservesMixedBody() throws {
        for eol in ["\r\n", "\r", "\n"] {
            let prefix = "\u{FEFF}first" + eol
            let body = "\u{FEFF}Cafe\u{301} 😀\r\nraw\rlast\nend"
            let suffix = "\r\nafter\n"
            let source = prefix + body + suffix
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: source,
                selection: NSRange(location: prefix.utf16.count, length: body.utf16.count)))
            let expected = "```" + eol + body + eol + "```"
            bytesEqual(plan.replacement, expected)
            bytesEqual(apply(plan), prefix + expected + suffix)
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
        }
    }

    func testCodeBlockSelectedTrailingEndingIsNotDuplicatedAndWhitespaceIsValid() throws {
        for body in ["body\r\n", "body\r", "body\n", " \t \n"] {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: body,
                selection: NSRange(location: 0, length: body.utf16.count)))
            let eol = body.hasSuffix("\r\n") ? "\r\n" : body.hasSuffix("\r") ? "\r" : "\n"
            bytesEqual(plan.replacement, "```" + eol + body + "```")
            bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
        }
        let spaces = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: "   ",
            selection: NSRange(location: 0, length: 3)))
        bytesEqual(spaces.replacement, "```\n   \n```")
    }

    func testCodeBlockFenceExceedsLongestRunWithoutInlineCodePadding() throws {
        let body = "`edge `` middle ```` end`"
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: body,
            selection: NSRange(location: 0, length: body.utf16.count)))
        bytesEqual(plan.replacement, "`````\n" + body + "\n`````")
        bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
        let ticks = String(repeating: "`", count: MarkdownInsertionPlan.maximumSelectionBytes)
        let maximum = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: ticks,
            selection: NSRange(location: 0, length: ticks.utf16.count)))
        XCTAssertEqual(maximum.replacement.utf8.count, 3 * ticks.utf8.count + 4)
        XCTAssertEqual(maximum.selectionAfter, NSRange(location: ticks.utf16.count + 2, length: ticks.utf16.count))
    }

    func testCodeBlockLeavesScriptShapedMultilineSourceInertAndExact() throws {
        let body = "<script>inert()</script>\r\n```unterminated\r[broken]("
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .codeBlock, source: body,
            selection: NSRange(location: 0, length: body.utf16.count)))
        bytesEqual(plan.source, body)
        bytesEqual(plan.replacement, "````\r\n" + body + "\r\n````")
        bytesEqual((apply(plan) as NSString).substring(with: plan.selectionAfter), body)
    }

    func testStructureCommandsShareStrictRangeByteAndOutputBounds() throws {
        let source = "😀a\r\nb"
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: Int.max),
                      NSRange(location: -1, length: 1), NSRange(location: 1, length: 0),
                      NSRange(location: 0, length: 1), NSRange(location: 4, length: 0)] {
            for command in commands {
                XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: source, selection: range))
            }
        }
        let body = String(repeating: "😀", count: MarkdownInsertionPlan.maximumSelectionBytes / 4)
        let oversizedSource = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes + 1)
        for command in commands {
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: oversizedSource,
                selection: NSRange(location: 0, length: 0)))
            XCTAssertNotNil(MarkdownInsertionPlan.make(command: command, source: body,
                selection: NSRange(location: 0, length: body.utf16.count)))
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: body + "x",
                selection: NSRange(location: 0, length: body.utf16.count + 1)))
            let sample = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: "x", selection: .init(location: 0, length: 0)))
            let boundary = String(repeating: "x", count: MarkdownInsertionPlan.maximumSourceBytes - sample.replacement.utf8.count)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: boundary, selection: .init(location: 0, length: 0)))
            XCTAssertEqual(apply(plan).utf8.count, MarkdownInsertionPlan.maximumSourceBytes)
            XCTAssertNil(MarkdownInsertionPlan.make(command: command, source: boundary + "x", selection: .init(location: 0, length: 0)))
        }
    }

    func testStructurePlansRetainExactStaleSourceAndRangeContract() throws {
        let source = "Café\r\n"
        let selection = NSRange(location: 0, length: 4)
        for command in commands {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: selection))
            XCTAssertTrue(plan.matches(source: source, selection: selection))
            XCTAssertFalse(plan.matches(source: "Cafe\u{301}\r\n", selection: selection))
            XCTAssertFalse(plan.matches(source: "Café\n", selection: selection))
            XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 0, length: 3)))
            bytesEqual(plan.source, source)
        }
    }
}
