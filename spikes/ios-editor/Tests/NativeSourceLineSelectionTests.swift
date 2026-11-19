import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Authored UIKit scope/refusal coverage; compilation and runtime are pending.
@MainActor final class NativeSourceLineSelectionTests: XCTestCase {
    func testLineSelectionRefusesDetachedAndBlockScopeWithoutChangingState() throws {
        let source = "\u{FEFF}first Cafe\u{301} 😀\r\nsecond\r"
        let selected = NSRange(location: 3, length: 2)
        let plan = try XCTUnwrap(SourceLineSelection.make(source: source, selection: selected))
        for scope in [true, false] {
            let view = SourceTextView()
            view.focusesOnAttachment = false
            view.allowsSourceLineSelection = scope
            view.text = source; view.selectedRange = selected
            XCTAssertFalse(view.applySourceLineSelection(plan))
            XCTAssertTrue(SourceSelection.sameText(view.text, source))
            XCTAssertEqual(view.selectedRange, selected)
            let action = view.makeSourceLineSelectionAction()
            XCTAssertEqual(action.title, SourceLineSelection.title)
            XCTAssertTrue(action.attributes.contains(.disabled))
        }
    }

    func testContextRangeMismatchAndFragmentScopeKeepExistingNativeActions() {
        let view = SourceTextView(); view.focusesOnAttachment = false
        view.text = "first\r\nsecond"
        let selected = NSRange(location: 1, length: 2)
        view.selectedRange = selected
        let coordinator = NativeSourceEditor.Coordinator { _, _, _ in }
        XCTAssertNil(coordinator.textView(view, editMenuForTextIn: NSRange(location: 0, length: 5), suggestedActions: []))
        XCTAssertEqual(view.selectedRange, selected)
        view.allowsMarkdownInsertion = false
        view.allowsSourceLineSelection = false
        let suggested = UIAction(title: "Native suggested action") { _ in }
        let menu = coordinator.textView(view, editMenuForTextIn: selected, suggestedActions: [suggested])
        XCTAssertEqual(menu?.children.count, 1)
        XCTAssertTrue(menu?.children.first === suggested)
        XCTAssertEqual(view.selectedRange, selected)
        XCTAssertEqual(view.text, "first\r\nsecond")
    }
}
