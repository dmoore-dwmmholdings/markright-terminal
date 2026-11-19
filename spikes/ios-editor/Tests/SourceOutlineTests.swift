import Foundation
import XCTest
@testable import MarkrightEditorSpike

final class SourceOutlineTests: XCTestCase {
    func testExactBOMUnicodeMixedEndingRangesAndPhysicalLines() throws {
        let source = "\u{FEFF}# Cafe\u{301} 😀\r\nbody\r  ## Two\n### Three"
        let outline = SourceOutline.make(source: source)
        XCTAssertNil(outline.message)
        XCTAssertEqual(outline.headings.map(\.level), [1, 2, 3])
        XCTAssertEqual(outline.headings.map(\.line), [1, 3, 4])
        XCTAssertEqual(outline.headings.map { (source as NSString).substring(with: $0.range) }, ["# Cafe\u{301} 😀", "  ## Two", "### Three"])
        XCTAssertEqual(outline.headings[0].range.location, 1)
        XCTAssertTrue(outline.source.utf8.elementsEqual(source.utf8))
        for heading in outline.headings { XCTAssertTrue(SourceSelection.isValid(heading.range, in: source)) }
    }

    func testATXBoundariesIndentAndLiteralLabels() {
        let source = "#\n##\tTwo **literal** ###\n   ###### Six\n####### Seven\n#word\n#\u{00A0}space\n    # indented\n\t# tab\nprefix # middle\n"
        let outline = SourceOutline.make(source: source)
        XCTAssertEqual(outline.headings.map(\.title), ["(empty heading)", "Two **literal** ###", "Six"])
        XCTAssertEqual(outline.headings.map(\.level), [1, 2, 6])
        XCTAssertEqual(outline.headings.map(\.line), [1, 2, 3])
        XCTAssertTrue(outline.headings[1].menuTitle.contains("line 2"))
    }

    func testFenceMarkerLengthAndClosingTail() {
        let source = "# Before\n````swift\n# hidden\n```\n# still hidden\n~~~~\n# hidden too\n```` prose\n# still fenced\n````` \t\n## After\n~~~info\n# hidden tilde\n~~~~\n### Final\n"
        XCTAssertEqual(SourceOutline.make(source: source).headings.map(\.title), ["Before", "After", "Final"])
    }

    func testUnclosedFenceAndIndentedFence() {
        for marker in ["```", "~~~~", "   ```swift"] {
            XCTAssertEqual(SourceOutline.make(source: "# Before\r" + marker + "\r# Hidden\r").headings.map(\.title), ["Before"])
        }
        XCTAssertEqual(SourceOutline.make(source: "    ```\n# Visible\n").headings.map(\.title), ["Visible"])
        let invalid = SourceOutline.make(source: "# Before\n```bad`info\n# Later\n")
        XCTAssertTrue(invalid.headings.isEmpty)
        XCTAssertTrue(invalid.message?.contains("unsupported fence") == true)
    }

    func testHTMLLikeSourceRefusesWholeReportOutsideFences() {
        for source in ["# Before\n<div>\n# False\n", "# title <tag>\n", "# Before\ncomparison < 3\n"] {
            let outline = SourceOutline.make(source: source)
            XCTAssertTrue(outline.headings.isEmpty)
            XCTAssertTrue(outline.message?.contains("HTML-like") == true)
        }
        let outline = SourceOutline.make(source: "```\n<div>\n# Hidden\n```\n# &lt;literal&gt;\n")
        XCTAssertNil(outline.message)
        XCTAssertEqual(outline.headings.map(\.title), ["&lt;literal&gt;"])
    }

    func testWholeReportByteAndHeadingLimitsWithoutSilentTruncation() {
        XCTAssertEqual(SourceOutline.make(source: String(repeating: "x", count: 65_536)).message, "No top-level ATX headings.")
        let exact = String(repeating: "x", count: 65_532) + "😀"
        XCTAssertFalse(SourceOutline.make(source: exact).message?.contains("64 KiB") == true)
        for source in [exact + "x", String(repeating: "😀", count: 16_385)] {
            let report = SourceOutline.make(source: source)
            XCTAssertTrue(report.headings.isEmpty)
            XCTAssertTrue(report.message?.contains("64 KiB") == true)
        }
        XCTAssertEqual(SourceOutline.make(source: String(repeating: "# title\n", count: 128)).headings.count, 128)
        let overflow = SourceOutline.make(source: String(repeating: "# title\n", count: 129))
        XCTAssertTrue(overflow.headings.isEmpty)
        XCTAssertTrue(overflow.message?.contains("128 headings") == true)
    }

    func testPlanBindsExactSourceAndMenuSelection() throws {
        let source = "# Cafe\u{301}\r\n## 😀 target\n"
        let outline = SourceOutline.make(source: source)
        let selection = NSRange(location: 2, length: 0)
        let plan = try XCTUnwrap(outline.plan(for: outline.headings[1], selection: selection))
        XCTAssertEqual(plan.destination, outline.headings[1].range)
        XCTAssertTrue(plan.matches(source: source, selection: selection))
        XCTAssertFalse(plan.matches(source: source + "x", selection: selection))
        XCTAssertFalse(plan.matches(source: source.precomposedStringWithCanonicalMapping, selection: selection))
        XCTAssertFalse(plan.matches(source: source, selection: NSRange(location: 3, length: 0)))
    }

    func testInvalidMenuSelectionAndForeignHeadingRefused() throws {
        let source = "# 😀\r\n## target"
        let outline = SourceOutline.make(source: source)
        for selection in [NSRange(location: 3, length: 0), NSRange(location: 5, length: 0), NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: Int.max)] {
            XCTAssertNil(outline.plan(for: outline.headings[1], selection: selection))
        }
        let foreign = SourceHeading(range: NSRange(location: Int.max, length: 1), level: 1, line: 1, title: "foreign")
        XCTAssertNil(outline.plan(for: foreign, selection: SourceSelection.beginning))
        let eof = try XCTUnwrap(outline.plan(for: outline.headings[0], selection: NSRange(location: source.utf16.count, length: 0)))
        XCTAssertTrue(eof.matches(source: source, selection: eof.selection))
    }

    func testLabelBoundsAndControlsDoNotChangeSourceOrRanges() {
        let body = String(repeating: "e\u{301}😀", count: 60) + "\u{0007}x\u{2028}y"
        let source = "# " + body
        let report = SourceOutline.make(source: source)
        XCTAssertEqual(report.headings.count, 1)
        XCTAssertEqual(report.headings[0].title.count, 81)
        XCTAssertTrue(report.headings[0].title.hasSuffix("…"))
        XCTAssertTrue((source as NSString).substring(with: report.headings[0].range).utf8.elementsEqual(source.utf8))
        XCTAssertEqual(SourceOutline.make(source: "# a\u{0007}b\u{2028}c").headings[0].title, "a b c")
    }

    func testOversizedCombiningTitleKeepsCompleteBOMSourceAndNavigationRange() throws {
        let huge = "e" + String(repeating: "\u{301}", count: 1_024)
        XCTAssertEqual(huge.count, 1, "Fixture must exercise a single large grapheme")
        let source = "\u{FEFF}# " + huge + "\r\n## Cafe\u{301} 😀\r"
        let report = SourceOutline.make(source: source)
        XCTAssertNil(report.message)
        XCTAssertEqual(report.headings.count, 2)
        let heading = try XCTUnwrap(report.headings.first)
        XCTAssertEqual(heading.title, "…")
        XCTAssertEqual(heading.range, NSRange(location: 1, length: 2 + huge.utf16.count))
        XCTAssertEqual(heading.line, 1)
        XCTAssertEqual(report.headings[1].line, 2)
        XCTAssertTrue(report.source.utf8.elementsEqual(source.utf8))
        XCTAssertTrue((source as NSString).substring(with: heading.range).utf8.elementsEqual(("# " + huge).utf8))
        let plan = try XCTUnwrap(report.plan(for: heading, selection: SourceSelection.beginning))
        XCTAssertEqual(plan.destination, heading.range)
        XCTAssertTrue(plan.matches(source: source, selection: SourceSelection.beginning))
        XCTAssertTrue(report.headings[1].title.utf8.elementsEqual("Cafe\u{301} 😀".utf8))
        XCTAssertTrue(heading.menuTitle.hasSuffix(": …"))
    }

    func testTitleUTF16BoundaryKeepsWholeCombiningAndSupplementaryGraphemes() throws {
        XCTAssertEqual(SourceOutline.maximumTitleCharacters, 80)
        XCTAssertEqual(SourceOutline.maximumTitleUTF16, 320)
        let prefix = String(repeating: "a", count: SourceOutline.maximumTitleCharacters - 1)
        let remaining = SourceOutline.maximumTitleUTF16 - prefix.utf16.count
        let exact = prefix + "e" + String(repeating: "\u{301}", count: remaining - 1)
        XCTAssertEqual(exact.count, SourceOutline.maximumTitleCharacters)
        XCTAssertEqual(exact.utf16.count, SourceOutline.maximumTitleUTF16)
        let exactHeading = try XCTUnwrap(SourceOutline.make(source: "# " + exact).headings.first)
        XCTAssertTrue(exactHeading.title.utf8.elementsEqual(exact.utf8))
        let over = exact + "\u{301}"
        XCTAssertEqual(over.count, SourceOutline.maximumTitleCharacters)
        let overHeading = try XCTUnwrap(SourceOutline.make(source: "# " + over).headings.first)
        XCTAssertEqual(overHeading.title, prefix + "…", "A clipped grapheme must be omitted whole")
        XCTAssertEqual(overHeading.range.length, 2 + over.utf16.count)

        let flags = String(repeating: "🇨🇦", count: SourceOutline.maximumTitleCharacters)
        XCTAssertEqual(flags.utf16.count, SourceOutline.maximumTitleUTF16)
        let flagHeading = try XCTUnwrap(SourceOutline.make(source: "# " + flags).headings.first)
        XCTAssertTrue(flagHeading.title.utf8.elementsEqual(flags.utf8))
        let extraHeading = try XCTUnwrap(SourceOutline.make(source: "# " + flags + "🇨🇦").headings.first)
        XCTAssertEqual(extraHeading.title, flags + "…")
        for heading in [exactHeading, overHeading, flagHeading, extraHeading] {
            XCTAssertLessThanOrEqual(heading.title.utf16.count, SourceOutline.maximumTitleUTF16 + 1)
            XCTAssertLessThanOrEqual(heading.title.count, SourceOutline.maximumTitleCharacters + 1)
        }
    }

    func testEmptyAndUnsupportedHeadingFormsAreExplicit() {
        for source in ["", "\u{FEFF}", "Title\n===\n", "> # Nested\n", "- # Item\n"] {
            let report = SourceOutline.make(source: source)
            XCTAssertTrue(report.headings.isEmpty)
            XCTAssertEqual(report.message, "No top-level ATX headings.")
        }
    }
}
