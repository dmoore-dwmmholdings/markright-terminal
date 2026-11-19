import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Compiled UIKit refusals only until a separately coordinated runtime run.
@MainActor final class NativeTaskMarkerEditTests: XCTestCase {
    func testTaskMarkerCaretPlanRefusesDetachedAndBlockScope() throws {
        let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n"
        let selection = NSRange(location: 9, length: 0)
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: selection))
        XCTAssertNotEqual(plan.range, selection)
        for scope in [true, false] {
            let view = SourceTextView()
            view.focusesOnAttachment = false
            view.allowsMarkdownInsertion = scope
            view.text = source
            view.selectedRange = selection
            XCTAssertFalse(view.applyMarkdownInsertion(plan))
            XCTAssertTrue(SourceSelection.sameText(view.text, source))
            XCTAssertEqual(view.selectedRange, selection)
            XCTAssertEqual(view.makeTaskMarkerAction().title, TaskMarkerEdit.title)
            XCTAssertTrue(view.makeTaskMarkerAction().attributes.contains(.disabled))
        }
    }
}

/// This fixture requires a coordinated synthetic simulator test session. It is
/// authored here but does not establish attached UIKit evidence by compilation.
@MainActor private final class RejectTaskInputDelegate: NSObject, UITextViewDelegate {
    var attemptedRanges: [NSRange] = []
    var attemptedReplacements: [String] = []
    var selectionOnRefusal: NSRange?
    var selectedRangeOnRefusal: NSRange?
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        attemptedRanges.append(range)
        attemptedReplacements.append(text)
        if let selectionOnRefusal { textView.selectedRange = selectionOnRefusal }
        selectedRangeOnRefusal = textView.selectedRange
        return false
    }
}

extension NativeTaskMarkerEditTests {
    func testAttachedNativeRefusalRestoresOnlyTheExpandedCaretSelection() throws {
        let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let scene = try XCTUnwrap(foregroundScenes.count == 1 ? foregroundScenes.first : nil,
                                 "Exactly one foreground synthetic test scene is required before creating a fixture window")
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let view = SourceTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 220))
        view.focusesOnAttachment = false
        controller.view.addSubview(view)
        let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n"
        let caret = NSRange(location: 9, length: 0)
        view.text = source
        view.selectedRange = caret
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: caret))
        let refusal = RejectTaskInputDelegate()
        view.delegate = refusal
        defer {
            let ownedKey = window.isKeyWindow
            view.resignFirstResponder()
            view.delegate = nil
            window.isHidden = true
            window.rootViewController = nil
            if ownedKey { oldKey?.makeKey() }
        }
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(view.becomeFirstResponder(), "Refusal positive control requires attached input focus")
        XCTAssertTrue(view.isFirstResponder && view.window === window)
        XCTAssertTrue(view.makeTaskMarkerAction().attributes.isEmpty, "Fresh attached task action must be available")
        XCTAssertFalse(view.applyMarkdownInsertion(plan))
        XCTAssertEqual(refusal.attemptedRanges, [plan.range], "Native input must actually consult the refusing delegate")
        XCTAssertTrue(SourceSelection.sameText(view.text, source))
        XCTAssertEqual(view.selectedRange, caret, "Refused task edit must not leave its temporary whole-row selection")
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertNil(view.markedTextRange)
        XCTAssertEqual(refusal.attemptedReplacements, [plan.replacement])

        // A delegate may decline while deliberately moving the caret. The
        // command must not replace that distinct state with its old caret.
        let distinct = NSRange(location: 1, length: 0)
        refusal.selectionOnRefusal = distinct
        XCTAssertFalse(view.applyMarkdownInsertion(plan))
        XCTAssertEqual(refusal.attemptedRanges, [plan.range, plan.range])
        XCTAssertEqual(refusal.attemptedReplacements, [plan.replacement, plan.replacement])
        XCTAssertEqual(refusal.selectedRangeOnRefusal, distinct, "Delegate caret positive control failed")
        XCTAssertEqual(view.selectedRange, distinct)
        XCTAssertTrue(SourceSelection.sameText(view.text, source))
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertNil(view.markedTextRange)
        XCTAssertFalse(view.undoManager?.canUndo ?? false, "A refused task edit must not leave a selection-only undo step")
    }

    func testAttachedTaskUndoRedoRestoresExactBytesAndCaret() throws {
        let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let scene = try XCTUnwrap(foregroundScenes.count == 1 ? foregroundScenes.first : nil,
                                 "Exactly one foreground synthetic test scene is required before creating a fixture window")
        let oldKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let view = SourceTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 220))
        view.focusesOnAttachment = false
        controller.view.addSubview(view)
        let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n* [X] two\r"
        let checked = "\u{FEFF}- [x] Cafe\u{301} 😀\r\n* [X] two\r"
        let caret = NSRange(location: 9, length: 0)
        view.text = source
        view.selectedRange = caret
        defer {
            let ownedKey = window.isKeyWindow
            view.resignFirstResponder()
            window.isHidden = true
            window.rootViewController = nil
            if ownedKey { oldKey?.makeKey() }
        }
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(view.becomeFirstResponder())
        let undo = try XCTUnwrap(view.undoManager)
        undo.removeAllActions()
        let plan = try XCTUnwrap(TaskMarkerEdit.make(source: source, selection: caret))
        XCTAssertTrue(view.applyMarkdownInsertion(plan))
        XCTAssertEqual(Array(view.text.utf8), Array(checked.utf8))
        XCTAssertEqual(view.selectedRange, caret)
        XCTAssertEqual(undo.undoActionName, TaskMarkerEdit.title)
        for _ in 0..<2 {
            undo.undo()
            XCTAssertEqual(Array(view.text.utf8), Array(source.utf8), "Undo must restore exact source bytes")
            XCTAssertEqual(view.selectedRange, caret, "Undo must restore the original caret")
            undo.redo()
            XCTAssertEqual(Array(view.text.utf8), Array(checked.utf8))
            XCTAssertEqual(view.selectedRange, caret)
        }
        XCTAssertTrue(view.isFirstResponder)
    }
}
