import XCTest
import UIKit
@testable import MarkrightEditorSpike
@MainActor final class EditorModelTests: XCTestCase {
    func testSourceRoundTripAndAtomicBlocks() {
        let source = "# title\n\n```swift\nx=1\n```\n|a|b|\n|-|-|\n|x|y|\n😀\n"
        let m = EditorModel(source: source)
        XCTAssertEqual(m.source, source)
        XCTAssertEqual(m.blocks.filter(\.atomic).count, 2)
    }
    func testCompositionPreventsSwitchingOrPreviewReplacement() {
        let m = EditorModel(source: "one\ntwo"); m.activate(0); m.composing = true
        m.activate(1); m.finish(); XCTAssertEqual(m.active, 0)
        m.update(0,"日本語"); XCTAssertEqual(m.source,"日本語\ntwo")
        m.composing = false; m.finish(); XCTAssertNil(m.active)
    }
    func testEditingOneBlockPreservesAdjacentSource() {
        let m = EditorModel(source: "first\n**middle**\nlast")
        m.update(1, "😀 edited\nnew line")
        XCTAssertEqual(m.source,"first\n😀 edited\nnew line\nlast")
    }
    func testEveryPhysicalLineEndingGroupsTheSameBlocksWithoutRewritingBytes() {
        for ending in ["\n", "\r\n", "\r"] {
            let source = ["before", "```swift", "value", "```", "|a|b|", "|-|-|", "|x|y|", "after", ""].joined(separator: ending)
            let model = EditorModel(source: source)
            XCTAssertEqual(Array(model.source.utf8), Array(source.utf8))
            XCTAssertEqual(model.blocks.map(\.id), [0, 1, 4, 7, 8])
            XCTAssertEqual(model.blocks.filter(\.atomic).count, 2)
            XCTAssertEqual(model.blocks[1].source, ["```swift", "value", "```"].joined(separator: ending))
            XCTAssertEqual(model.blocks[1].separatorAfter, ending)
        }
    }
    func testMixedEndingsAndBOMSurviveEditingAnOrdinaryBlock() {
        let source = "\u{FEFF}first\r\n**middle**\rlast\n"
        let model = EditorModel(source: source)
        XCTAssertEqual(model.blocks.map(\.source), ["\u{FEFF}first", "**middle**", "last", ""])
        model.update(1, "😀 edited\nnew line")
        let expected = "\u{FEFF}first\r\n😀 edited\nnew line\rlast\n"
        XCTAssertEqual(Array(model.source.utf8), Array(expected.utf8))
        XCTAssertEqual(model.blocks.map(\.separatorAfter), ["\r\n", "\r", "\n", ""])
    }
    func testMixedAtomicBlockEndingsAndEmptyEOFRemainExact() {
        for source in ["", "\r\n", "\r", "\n", "```swift\r\nvalue\r```\nafter\r\n", "```swift\r\nvalue\r"] {
            let model = EditorModel(source: source)
            XCTAssertEqual(Array(model.source.utf8), Array(source.utf8))
        }
        let model = EditorModel(source: "before\r```swift\r\nvalue\r```\nafter\r\n")
        model.update(1, "```swift\r\nchanged\r```")
        XCTAssertEqual(Array(model.source.utf8), Array("before\r```swift\r\nchanged\r```\nafter\r\n".utf8))
    }
    func testNativeTextViewAtomicEditPreservesMixedEndingsAndNeighbors() throws {
        let source = "\u{FEFF}before 😀\r\n```swift\r\nvalue\r```\nafter e\u{301}\r"
        let model = EditorModel(source: source)
        let block = model.blocks[1]
        XCTAssertTrue(block.atomic)
        let view = UITextView()
        view.text = block.source
        let coordinator = NativeSourceEditor.Coordinator { value, composing in
            model.composing = composing
            model.update(block.id, value)
        }
        view.delegate = coordinator
        XCTAssertEqual(Array(view.text.utf8), Array(block.source.utf8))
        let valueRange = (view.text as NSString).range(of: "value")
        XCTAssertNotEqual(valueRange.location, NSNotFound)
        let start = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: valueRange.location))
        let end = try XCTUnwrap(view.position(from: start, offset: valueRange.length))
        let range = try XCTUnwrap(view.textRange(from: start, to: end))
        view.replace(range, withText: "changed 😀")
        coordinator.textViewDidChange(view)
        let expected = "\u{FEFF}before 😀\r\n```swift\r\nchanged 😀\r```\nafter e\u{301}\r"
        XCTAssertEqual(Array(model.source.utf8), Array(expected.utf8))
        XCTAssertEqual(model.blocks[0].source, "\u{FEFF}before 😀")
        XCTAssertEqual(model.blocks[2].source, "after e\u{301}")
        XCTAssertFalse(model.composing)
    }
    func testWholeSourceModeKeepsExactSourceAndRegroupsStructuralEditsOnExit() {
        let original = "\u{FEFF}before\r\ntext\rafter\n"
        let model = EditorModel(source: original)
        model.activate(1)
        model.showSource()
        XCTAssertTrue(model.sourceMode)
        XCTAssertNil(model.active)
        XCTAssertEqual(Array(model.source.utf8), Array(original.utf8))
        let changed = "\u{FEFF}before\r\n```swift\rvalue\n```\rafter\n"
        model.updateDocumentSource(changed, composing: false, generation: model.editingGeneration)
        XCTAssertEqual(Array(model.source.utf8), Array(changed.utf8))
        model.finish()
        XCTAssertFalse(model.sourceMode)
        XCTAssertEqual(model.documentSource, "")
        XCTAssertEqual(Array(model.source.utf8), Array(changed.utf8))
        XCTAssertEqual(model.blocks.filter(\.atomic).count, 1)
        XCTAssertEqual(model.blocks[1].source, "```swift\rvalue\n```")
    }
    func testWholeSourceModeCannotSwitchDuringMarkedTextOrAcceptLateTeardown() {
        let model = EditorModel(source: "original")
        model.composing = true
        model.showSource()
        XCTAssertFalse(model.sourceMode)
        model.composing = false
        model.showSource()
        let oldGeneration = model.editingGeneration
        model.composing = true
        model.updateDocumentSource("composing に", composing: true, generation: oldGeneration)
        model.finish()
        XCTAssertTrue(model.sourceMode)
        model.composing = false
        model.finish()
        model.updateDocumentSource("late old view callback", composing: true, generation: oldGeneration)
        XCTAssertEqual(model.source, "composing に")
        XCTAssertFalse(model.composing)
        model.showSource()
        model.updateDocumentSource("stale after re-entry", composing: true, generation: oldGeneration)
        XCTAssertEqual(model.source, "composing に")
        XCTAssertFalse(model.composing)
        model.updateDocumentSource("current generation", composing: true, generation: model.editingGeneration)
        model.updateDocumentSource("stale clears composition", composing: false, generation: oldGeneration)
        XCTAssertTrue(model.composing)
        XCTAssertEqual(model.source, "current generation")
    }
    func testOldBlockCallbackCannotOverwriteRegroupedSourceOrCurrentComposition() {
        let model = EditorModel(source: "first\nold\nlast")
        model.activate(1)
        let oldGeneration = model.editingGeneration
        model.showSource()
        model.updateDocumentSource("first\nnew\nlast", composing: false, generation: model.editingGeneration)
        model.finish()
        model.activate(1)
        model.updateBlockFromEditor(1, "new に", composing: true, generation: model.editingGeneration)
        model.updateBlockFromEditor(1, "old teardown", composing: false, generation: oldGeneration)
        XCTAssertTrue(model.composing)
        XCTAssertEqual(model.source, "first\nnew に\nlast")
    }
    func testNativeMarkedTextDefersPreviewUntilCommitted() {
        let model = EditorModel(source: "source"); model.activate(0)
        let view = UITextView(); view.text = "source"
        let coordinator = NativeSourceEditor.Coordinator { source, composing in
            model.composing = composing; model.update(0, source)
        }
        view.delegate = coordinator
        view.selectedRange = NSRange(location: 1, length: 0)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        coordinator.textViewDidChange(view)
        XCTAssertTrue(model.composing); model.finish(); XCTAssertEqual(model.active, 0)
        view.unmarkText(); coordinator.textViewDidChangeSelection(view)
        XCTAssertFalse(model.composing); XCTAssertEqual(model.source, "sにource")
        model.finish(); XCTAssertNil(model.active)
    }

    func testComposingEditorTeardownCommitsSourceAndClearsGuard() {
        let model = EditorModel(source: "source"); model.activate(0)
        let view = UITextView(); view.text = "source"
        let coordinator = NativeSourceEditor.Coordinator { source, composing in
            model.composing = composing; model.update(0, source)
        }
        view.delegate = coordinator; view.selectedRange = NSRange(location: 1, length: 0)
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        coordinator.textViewDidChange(view); XCTAssertTrue(model.composing)
        NativeSourceEditor.dismantleUIView(view, coordinator: coordinator)
        XCTAssertNil(view.markedTextRange); XCTAssertFalse(model.composing)
        XCTAssertEqual(model.source, "sにource"); model.finish(); XCTAssertNil(model.active)
    }

}
