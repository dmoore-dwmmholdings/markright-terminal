import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// UIKit unit coverage is compiled by the native shard. Runtime interaction and
/// real edit-menu/input-method acceptance require an available simulator/device.
@MainActor final class NativeMarkdownInsertionTests: XCTestCase {
    func testDetachedViewRefusesAValidPlanWithoutChangingSourceOrSelection() throws {
        let view = SourceTextView()
        view.focusesOnAttachment = false
        let source = "\u{FEFF}A cafe\u{301} 😀\r\nnext\r"
        view.text = source
        let selection = (source as NSString).range(of: "cafe\u{301}")
        view.selectedRange = selection
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: source, selection: selection))
        XCTAssertFalse(view.applyMarkdownInsertion(plan))
        XCTAssertTrue(SourceSelection.sameText(view.text, source))
        XCTAssertEqual(view.selectedRange, selection)
    }

    func testUnavailableNativeMenuHasExplicitlyDisabledCommands() {
        let view = SourceTextView()
        view.focusesOnAttachment = false
        view.text = "literal"
        view.selectedRange = NSRange(location: 0, length: 7)
        view.isEditable = false
        let menu = view.makeMarkdownMenu()
        XCTAssertEqual(menu.title, "Insert Markdown")
        XCTAssertEqual(menu.children.count, MarkdownInsertionCommand.allCases.count)
        for child in menu.children {
            guard let action = child as? UIAction else { return XCTFail("Expected a native Markdown action") }
            XCTAssertTrue(action.attributes.contains(.disabled))
        }
    }

    func testDelegateDoesNotRepointTheSelectionToItsContextRange() {
        let view = SourceTextView()
        view.focusesOnAttachment = false
        view.text = "one two"
        let selection = NSRange(location: 4, length: 3)
        view.selectedRange = selection
        var callbacks = 0
        let coordinator = NativeSourceEditor.Coordinator { _, _, _ in callbacks += 1 }
        let menu = coordinator.textView(view, editMenuForTextIn: NSRange(location: 0, length: 3), suggestedActions: [])
        XCTAssertNil(menu)
        XCTAssertEqual(view.selectedRange, selection)
        XCTAssertEqual(view.text, "one two")
        XCTAssertEqual(callbacks, 0)
    }

    func testBlockEditorScopeKeepsOnlySuggestedActionsAndRefusesInsertion() throws {
        let view = SourceTextView()
        view.focusesOnAttachment = false
        view.allowsMarkdownInsertion = false
        view.text = "block"
        let selection = NSRange(location: 0, length: 5)
        view.selectedRange = selection
        let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .bold, source: view.text, selection: selection))
        let suggested = UIAction(title: "Suggested native action") { _ in }
        let coordinator = NativeSourceEditor.Coordinator { _, _, _ in }
        let menu = coordinator.textView(view, editMenuForTextIn: selection, suggestedActions: [suggested])
        XCTAssertEqual(menu?.children.count, 1)
        XCTAssertTrue(menu?.children.first === suggested)
        XCTAssertTrue(view.makeMarkdownMenu().children.isEmpty)
        XCTAssertFalse(view.applyMarkdownInsertion(plan))
        XCTAssertEqual(view.text, "block")
        XCTAssertEqual(view.selectedRange, selection)
    }
}
