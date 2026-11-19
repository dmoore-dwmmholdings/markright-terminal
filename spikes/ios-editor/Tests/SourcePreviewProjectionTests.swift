import Foundation
import XCTest
@testable import MarkrightEditorSpike

private actor PreviewSaveCounter {
    private var count = 0
    func save(_ document: StoredDocument, source: String) -> StoredDocument {
        count += 1
        return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8))
    }
    func calls() -> Int { count }
}

@MainActor final class SourcePreviewProjectionTests: XCTestCase {
    private func projection(_ source: String, selection: NSRange = .init(location: 0, length: 0),
                            composing: Bool = false) -> SourcePreviewProjection {
        SourcePreviewProjection.make(source: source, selection: selection, composing: composing)
    }

    private func bytesEqual(_ actual: String, _ expected: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(actual.utf8.elementsEqual(expected.utf8), "Source bytes differ", file: file, line: line)
    }

    func testRowsAndOwnedRangesReconstructExactBOMNFDUnicodeAndMixedEndings() throws {
        let source = "\u{FEFF}Cafe\u{301} 😀\r\n**second**\rthird\n"
        let result = projection(source)
        XCTAssertEqual(result.state, .ready)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.rows.count, 4)
        bytesEqual(result.rows.map { $0.source + $0.separatorAfter }.joined(), source)
        let original = source as NSString
        var expectedStart = 0
        for row in result.rows {
            XCTAssertEqual(row.id, expectedStart)
            XCTAssertEqual(row.range.location, expectedStart)
            XCTAssertEqual(row.range.length, row.source.utf16.count + row.separatorAfter.utf16.count)
            bytesEqual(original.substring(with: row.range), row.source + row.separatorAfter)
            expectedStart += row.range.length
        }
        XCTAssertEqual(expectedStart, original.length)
        XCTAssertEqual(Set(result.rows.map(\.id)).count, result.rows.count)
        XCTAssertEqual(result.rows.map(\.separatorAfter), ["\r\n", "\r", "\n", ""])
    }

    func testFixtureHeaderFenceAndTableGroupsKeepAtomicSourceAndRanges() throws {
        let source = "# Header\r\n```swift\rvalue\n```\r\n| A | B |\r| --- | --- |\n| x | y |\rafter"
        let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.rows.count, 4)
        XCTAssertEqual(result.rows[0].source, "# Header")
        XCTAssertFalse(result.rows[0].isLiteral)
        bytesEqual(result.rows[1].source, "```swift\rvalue\n```")
        bytesEqual(result.rows[2].source, "| A | B |\r| --- | --- |\n| x | y |")
        XCTAssertTrue(result.rows[1].isLiteral)
        XCTAssertTrue(result.rows[2].isLiteral)
        XCTAssertFalse(result.rows[1].isActive)
        XCTAssertFalse(result.rows[2].isActive)
        bytesEqual(result.rows.map { $0.source + $0.separatorAfter }.joined(), source)
        let caret = result.rows[1].range.location + "```swift\r".utf16.count
        let active = projection(source, selection: NSRange(location: caret, length: 0))
        XCTAssertEqual(active.rows.filter(\.isActive).map(\.id), [result.rows[1].id])
        XCTAssertEqual(active.rows[1].display, AttributedString(active.rows[1].source))
        let crossed = projection(source, selection: NSRange(location: result.rows[1].range.location,
            length: result.rows[1].range.length + 1))
        XCTAssertEqual(crossed.rows.filter(\.isActive).map(\.id), [result.rows[1].id, result.rows[2].id])
        XCTAssertTrue(crossed.rows[1].isLiteral)
        XCTAssertTrue(crossed.rows[2].isLiteral)
    }

    func testCaretSeparatorsHalfOpenIntersectionsAndEOFHaveExactOwnership() {
        let source = "a\r\nb\nc\r"
        for (range, active) in [
            (NSRange(location: 0, length: 0), [0]),
            (NSRange(location: 1, length: 0), [0]),
            (NSRange(location: 3, length: 0), [3]),
            (NSRange(location: 4, length: 0), [3]),
            (NSRange(location: 5, length: 0), [5]),
            (NSRange(location: 7, length: 0), [7]),
            (NSRange(location: 1, length: 2), [0]),
            (NSRange(location: 3, length: 2), [3]),
            (NSRange(location: 1, length: 3), [0, 3]),
            (NSRange(location: 4, length: 3), [3, 5]),
            (NSRange(location: 0, length: 7), [0, 3, 5])
        ] {
            let result = projection(source, selection: range)
            XCTAssertEqual(result.state, .ready)
            XCTAssertEqual(result.rows.filter(\.isActive).map(\.id), active, String(describing: range))
        }
        let eof = projection("last", selection: NSRange(location: 4, length: 0))
        XCTAssertTrue(eof.rows[0].isActive)
        let empty = projection("")
        XCTAssertEqual(empty.rows.count, 1)
        XCTAssertEqual(empty.rows[0].range, NSRange(location: 0, length: 0))
        XCTAssertTrue(empty.rows[0].isActive)
        XCTAssertEqual(empty.rows[0].display, AttributedString(""))
    }

    func testInvalidRangesClearRowsBeforeIntersectionArithmetic() {
        let source = "😀a\r\nb"
        for range in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: Int.max, length: Int.max),
                      NSRange(location: 1, length: 0), NSRange(location: 0, length: 1),
                      NSRange(location: 4, length: 0), NSRange(location: 3, length: 1),
                      NSRange(location: 0, length: source.utf16.count + 1)] {
            let result = projection(source, selection: range)
            XCTAssertEqual(result.state, .invalidSelection)
            XCTAssertTrue(result.rows.isEmpty)
            XCTAssertNotNil(result.message)
        }
    }

    func testCompositionShortCircuitsSizeRowsAndInvalidSelectionWithNoStaleRows() {
        let source = String(repeating: "**many**\n", count: SourcePreviewProjection.maximumBytes)
        let result = projection(source, selection: NSRange(location: Int.max, length: Int.max), composing: true)
        XCTAssertEqual(result.state, .composing)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertNotNil(result.message)
        let ready = projection("**ready**\nactive", selection: NSRange(location: 15, length: 0))
        XCTAssertEqual(ready.state, .ready)
        let paused = projection("**ready**\nactive", composing: true)
        XCTAssertEqual(paused.state, .composing)
        XCTAssertTrue(paused.rows.isEmpty)
    }

    func testByteAndGroupedRowBudgetsFailExplicitlyWithoutTruncation() {
        let maximum = String(repeating: "😀", count: SourcePreviewProjection.maximumBytes / 4)
        let exact = projection(maximum)
        XCTAssertEqual(exact.state, .ready)
        bytesEqual(exact.rows.map { $0.source + $0.separatorAfter }.joined(), maximum)
        let over = projection(maximum + "x")
        XCTAssertEqual(over.state, .tooLarge)
        XCTAssertTrue(over.rows.isEmpty)
        XCTAssertNotNil(over.message)
        let rowBoundary = String(repeating: "x\n", count: SourcePreviewProjection.maximumRows - 1)
        let rows = projection(rowBoundary)
        XCTAssertEqual(rows.state, .ready)
        XCTAssertEqual(rows.rows.count, SourcePreviewProjection.maximumRows)
        bytesEqual(rows.rows.map { $0.source + $0.separatorAfter }.joined(), rowBoundary)
        let tooMany = projection(rowBoundary + "x\n")
        XCTAssertEqual(tooMany.state, .tooManyRows)
        XCTAssertTrue(tooMany.rows.isEmpty)
        XCTAssertNotNil(tooMany.message)
        // The cap concerns the existing fixture groups, not physical code lines.
        let atomic = "```\n" + String(repeating: "x\n", count: 300) + "```"
        let grouped = projection(atomic)
        XCTAssertEqual(grouped.state, .ready)
        XCTAssertEqual(grouped.rows.count, 1)
        XCTAssertTrue(grouped.rows[0].isLiteral)
    }

    func testInlineUTF16BudgetUsesBodyUnitsAndActiveRowsAlwaysStayLiteral() {
        for (body, literal) in [
            (String(repeating: "x", count: SourcePreviewProjection.maximumInlineUTF16), false),
            (String(repeating: "x", count: SourcePreviewProjection.maximumInlineUTF16 + 1), true),
            (String(repeating: "😀", count: SourcePreviewProjection.maximumInlineUTF16 / 2), false),
            (String(repeating: "😀", count: SourcePreviewProjection.maximumInlineUTF16 / 2 + 1), true)
        ] {
            let source = body + "\r\nactive"
            let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
            XCTAssertEqual(result.rows[0].isLiteral, literal)
        }
        let source = "**bold**\nactive"
        let inactive = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
        XCTAssertFalse(inactive.rows[0].isLiteral)
        XCTAssertEqual(String(inactive.rows[0].display.characters), "bold")
        let active = projection(source)
        XCTAssertTrue(active.rows[0].isLiteral)
        XCTAssertEqual(active.rows[0].display, AttributedString("**bold**"))
    }

    func testUnsupportedMarkupUsesUnattributedLiteralText() {
        for body in ["<b>HTML</b>", "![alt](file:///tmp/image.png)", "a ``` fence", "a ~~~ fence", "{% inert %}", "{{ inert }}"] {
            let source = body + "\nactive"
            let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
            XCTAssertTrue(result.rows[0].isLiteral, body)
            XCTAssertEqual(result.rows[0].display, AttributedString(body))
            XCTAssertTrue(result.rows.allSatisfy { $0.display.runs.allSatisfy { $0.link == nil } })
        }
    }

    func testLinksLoseURLAttributesAcrossSchemesWithoutChangingOriginalSource() {
        for destination in ["https://example.invalid", "file:///tmp/inert", "javascript:inert()", "data:text/plain,inert", "mailto:inert@example.invalid", "custom:inert"] {
            let body = "[read](\(destination))"
            let source = body + "\nactive"
            let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
            XCTAssertFalse(result.rows[0].isLiteral)
            bytesEqual(result.rows[0].source, body)
            XCTAssertTrue(result.rows.allSatisfy { $0.display.runs.allSatisfy { $0.link == nil } })
            let literal = projection(source)
            XCTAssertEqual(literal.rows[0].display, AttributedString(body))
            XCTAssertTrue(literal.rows[0].display.runs.allSatisfy { $0.link == nil })
        }
    }

    func testUnsupportedFenceLikeSyntaxKeepsWholeReportLiteralWithoutRegrouping() throws {
        for source in [
            "~~~\n**code**\n~~~",
            "  ```swift\r\n**code**\r\n  ```\r\n**outside**\r\ncaret",
            "~~~incomplete\r**code**\r**outside**\rcaret",
            "    ```incomplete\n**code**\ncaret"
        ] {
            let fixture = EditorModel(source: source).blocks
            let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
            XCTAssertEqual(result.state, .ready)
            XCTAssertEqual(result.message, "Unsupported fence-like syntax; preview remains literal.")
            XCTAssertEqual(result.rows.count, fixture.count)
            bytesEqual(result.rows.map { $0.source + $0.separatorAfter }.joined(), source)
            XCTAssertTrue(result.rows.allSatisfy(\.isLiteral))
            let last = try XCTUnwrap(result.rows.last)
            XCTAssertEqual(result.rows.filter(\.isActive).map(\.id), [last.id])
            for row in result.rows {
                XCTAssertEqual(row.display, AttributedString(row.source))
                XCTAssertTrue(row.display.runs.allSatisfy { $0.link == nil })
                bytesEqual((source as NSString).substring(with: row.range), row.source + row.separatorAfter)
            }
        }
    }

    func testRecognizedAtomicBacktickFenceStillAllowsOrdinaryOutsideInlinePreview() {
        let source = "**outside**\n```swift\n**code**\n```\ncaret"
        let result = projection(source, selection: NSRange(location: source.utf16.count, length: 0))
        XCTAssertEqual(result.state, .ready)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertFalse(result.rows[0].isLiteral)
        XCTAssertEqual(String(result.rows[0].display.characters), "outside")
        XCTAssertTrue(result.rows[1].isLiteral)
        XCTAssertEqual(result.rows[1].display, AttributedString("```swift\n**code**\n```"))
        bytesEqual(result.rows.map { $0.source + $0.separatorAfter }.joined(), source)
    }

    func testProjectionDoesNotMutateSessionEditorIdentitySourceSelectionOrSaveState() async {
        let saves = PreviewSaveCounter()
        let session = DocumentSession(document: StoredDocument(collection: "Notes", name: "note.mrk", source: "original", baseline: Data("original".utf8))) {
            await saves.save($0, source: $1)
        }
        let model = session.model
        model.showSource()
        let source = "\u{FEFF}Cafe\u{301} 😀\r\n**next**\r"
        let selection = NSRange(location: 2, length: 3)
        model.updateDocumentSource(source, composing: false, generation: model.editingGeneration, selection: selection)
        let generation = model.editingGeneration
        let revision = model.sourceRevision
        let baseline = session.document.baseline
        let result = projection(model.source, selection: model.documentSelection, composing: model.composing)
        XCTAssertEqual(result.state, .ready)
        XCTAssertTrue(session.model === model)
        bytesEqual(model.source, source)
        XCTAssertEqual(model.documentSelection, selection)
        XCTAssertEqual(model.editingGeneration, generation)
        XCTAssertEqual(model.sourceRevision, revision)
        XCTAssertEqual(session.document.baseline, baseline)
        XCTAssertEqual(session.savedRevision, 0)
        XCTAssertTrue(session.dirty)
        XCTAssertFalse(session.canClose)
        XCTAssertTrue(model.sourceMode)
        XCTAssertFalse(model.composing)
        XCTAssertNil(session.recoveryDraft)
        let count = await saves.calls()
        XCTAssertEqual(count, 0)
    }
}
