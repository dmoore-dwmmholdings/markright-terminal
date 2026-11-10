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
