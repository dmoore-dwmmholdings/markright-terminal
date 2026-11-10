import XCTest
import UIKit
@testable import MarkrightEditorSpike

@MainActor final class NativeSelectionTests: XCTestCase {
    func testInvalidAndStaleBlockRangesNeverBecomeDifferentBookmarks() {
        let model = EditorModel(source: "first\n😀middle")
        model.activate(1)
        model.updateBlockFromEditor(1, "😀middle", composing: false, generation: model.editingGeneration, selection: NSRange(location: 1, length: 0))
        model.showSource()
        XCTAssertEqual(model.documentSelection, SourceSelection.beginning)
        XCTAssertEqual(model.source, "first\n😀middle")

        let current = EditorModel(source: "first\nmiddle")
        current.activate(1); let oldGeneration = current.editingGeneration
        current.updateBlockFromEditor(1, "middle", composing: false, generation: oldGeneration, selection: NSRange(location: 2, length: 2))
        current.finish(); current.activate(1)
        let range = NSRange(location: 3, length: 1)
        current.updateBlockFromEditor(1, "middle", composing: false, generation: current.editingGeneration, selection: range)
        current.updateBlockFromEditor(1, "stale", composing: true, generation: oldGeneration, selection: SourceSelection.beginning)
        XCTAssertEqual(current.selection(for: 1), range)
        XCTAssertFalse(current.composing)
        XCTAssertEqual(current.source, "first\nmiddle")
    }
    func testUTF16ValidationRejectsInvalidBoundariesWithoutOverflow() {
        for range in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1),
                      NSRange(location: NSNotFound, length: 0), NSRange(location: 1, length: Int.max),
                      NSRange(location: 4, length: 0)] {
            XCTAssertFalse(SourceSelection.isValid(range, in: "😀x"))
        }
        XCTAssertFalse(SourceSelection.isValid(NSRange(location: 1, length: 0), in: "😀x"))
        XCTAssertFalse(SourceSelection.isValid(NSRange(location: 0, length: 1), in: "😀x"))
        XCTAssertFalse(SourceSelection.isValid(NSRange(location: 2, length: 0), in: "a\r\nb"))
        XCTAssertFalse(SourceSelection.isValid(NSRange(location: 0, length: 2), in: "a\r\nb"))
        for (source, range) in [("", SourceSelection.beginning), ("😀x", NSRange(location: 2, length: 1)),
                                ("e\u{301}", NSRange(location: 1, length: 0)), ("a\r\nb", NSRange(location: 3, length: 1)),
                                ("a\rb\n", NSRange(location: 1, length: 2))] {
            XCTAssertTrue(SourceSelection.isValid(range, in: source))
        }
    }
    func testBlockSelectionMapsToExactDocumentAndSurvivesReadingAndRegrouping() {
        let source = "\u{FEFF}head😀\r\nA **bold** line\rafter\n"
        let model = EditorModel(source: source)
        model.activate(1)
        let block = model.blocks[1], range = (block.source as NSString).range(of: "bold")
        model.updateBlockFromEditor(1, block.source, composing: false, generation: model.editingGeneration, selection: range)
        model.finish(); model.activate(1)
        XCTAssertEqual(model.selection(for: 1), range)
        model.showSource()
        let global = NSRange(location: "\u{FEFF}head😀\r\n".utf16.count + range.location, length: range.length)
        XCTAssertEqual(model.documentSelection, global)
        model.setReadingMode(true); model.setReadingMode(false); model.showSource()
        XCTAssertEqual(model.documentSelection, global)
        model.finish(); model.activate(1)
        XCTAssertEqual(model.selection(for: 1), range)
        XCTAssertEqual(Array(model.source.utf8), Array(source.utf8))
    }
    func testCanonicalEquivalentEditsInvalidateSourceRevisionAndBookmarks() {
        XCTAssertEqual("é", "e\u{301}")
        XCTAssertFalse(SourceSelection.sameText("é", "e\u{301}"))
        let model = EditorModel(source: "e\u{301}\nnext")
        model.activate(0)
        model.updateBlockFromEditor(0, "e\u{301}", composing: false, generation: model.editingGeneration, selection: NSRange(location: 2, length: 0))
        model.showSource(); XCTAssertEqual(model.documentSelection.location, 2)
        model.finish(); model.update(0, "é"); model.showSource()
        XCTAssertEqual(model.documentSelection, SourceSelection.beginning)
        XCTAssertEqual(Array(model.source.utf8), Array("é\nnext".utf8))
        model.updateDocumentSource("e\u{301}\nnext", composing: false, generation: model.editingGeneration)
        XCTAssertEqual(model.documentSelection, SourceSelection.beginning)
        XCTAssertEqual(Array(model.source.utf8), Array("e\u{301}\nnext".utf8))
    }
    func testInvalidRangesRetainEditsAndStaleCallbacksCannotAlterSelectionOrComposition() {
        let model = EditorModel(source: "original")
        model.showSource(); let oldGeneration = model.editingGeneration
        model.updateDocumentSource("😀changed", composing: false, generation: oldGeneration, selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(model.source, "😀changed")
        XCTAssertEqual(model.documentSelection, SourceSelection.beginning)
        model.updateDocumentSource("😀changed", composing: false, generation: oldGeneration, selection: NSRange(location: 2, length: 3))
        model.setReadingMode(true); model.setReadingMode(false); model.showSource()
        XCTAssertEqual(model.documentSelection, NSRange(location: 2, length: 3))
        model.updateDocumentSource("stale", composing: true, generation: oldGeneration, selection: SourceSelection.beginning)
        XCTAssertFalse(model.composing)
        XCTAssertEqual(model.source, "😀changed")
        XCTAssertEqual(model.documentSelection, NSRange(location: 2, length: 3))
    }
    func testGlobalSelectionsRequireContainmentAndPreserveDocumentOnlySpans() {
        let model = EditorModel(source: "first\r\nsecond\rthird\n")
        let spanning = NSRange(location: 1, length: 8)
        model.showSource()
        model.updateDocumentSource(model.source, composing: false, generation: model.editingGeneration, selection: spanning)
        model.finish(); model.showSource()
        XCTAssertEqual(model.documentSelection, spanning)
        model.finish(); model.activate(1)
        XCTAssertEqual(model.selection(for: 1), SourceSelection.beginning)
        for (source, global, id, local) in [("first\nsecond", 5, 0, 5), ("first\nsecond", 6, 1, 0), ("a\n", 2, 1, 0)] {
            let m = EditorModel(source: source); m.showSource()
            m.updateDocumentSource(source, composing: false, generation: m.editingGeneration, selection: NSRange(location: global, length: 0))
            m.finish(); m.activate(id)
            XCTAssertEqual(m.selection(for: id), NSRange(location: local, length: 0))
        }
    }
    func testUnrelatedBlockEditsKeepLocalBookmarksButInvalidateDocumentCoordinates() {
        let model = EditorModel(source: "first\nsecond")
        model.activate(1)
        model.updateBlockFromEditor(1, "second", composing: false, generation: model.editingGeneration, selection: NSRange(location: 3, length: 1))
        model.finish(); model.update(0, "longer first")
        model.showSource(); XCTAssertEqual(model.documentSelection, SourceSelection.beginning)
        model.finish(); model.activate(1)
        // Whole-source regrouping invalidates old per-block IDs/bookmarks.
        XCTAssertEqual(model.selection(for: 1), SourceSelection.beginning)
        model.updateBlockFromEditor(1, "second", composing: false, generation: model.editingGeneration, selection: NSRange(location: 2, length: 2))
        model.finish(); model.update(0, "another first"); model.activate(1)
        XCTAssertEqual(model.selection(for: 1), NSRange(location: 2, length: 2))
    }
    func testActualTextViewRestoresRangeAndPreservesMarkedTextDuringUpdates() {
        let source = "\u{FEFF}a😀\r\nbold\rnext\n"
        let view = UITextView(); view.text = source
        let range = (source as NSString).range(of: "bold")
        NativeSourceEditor.restoreSelection(range, in: view)
        XCTAssertEqual(view.selectedRange, range)
        view.insertText("X")
        XCTAssertEqual(Array(view.text.utf8), Array((source as NSString).replacingCharacters(in: range, with: "X").utf8))
        view.text = "e\u{301}"; NativeSourceEditor.apply("é", selection: NSRange(location: 1, length: 0), to: view)
        XCTAssertEqual(Array(view.text.utf8), Array("é".utf8))
        XCTAssertEqual(view.selectedRange, NSRange(location: 1, length: 0))
        view.text = "source"; view.selectedRange = NSRange(location: 1, length: 0)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        let markedSource = view.text, markedSelection = view.selectedRange
        NativeSourceEditor.apply("external", selection: SourceSelection.beginning, to: view)
        XCTAssertNotNil(view.markedTextRange)
        XCTAssertEqual(view.text, markedSource); XCTAssertEqual(view.selectedRange, markedSelection)
    }
    func testLargeWholeSourceCaretRoundTripDoesNotChangeSource() {
        let source = String(repeating: "plain **bold** text\r\n", count: 50_000)
        let model = EditorModel(source: source); model.showSource()
        let end = NSRange(location: source.utf16.count, length: 0)
        model.updateDocumentSource(source, composing: false, generation: model.editingGeneration, selection: end)
        model.setReadingMode(true); model.setReadingMode(false); model.showSource()
        XCTAssertEqual(model.documentSelection, end)
        XCTAssertTrue(SourceSelection.sameText(model.source, source))
    }
}
