import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Compile-only UIKit coverage until the native shard runs on an available
/// simulator/device; this does not establish native menu or undo acceptance.
@MainActor final class NativeMarkdownListInsertionTests: XCTestCase {
    func testValidListPlansStayInertWhenDetachedOrOutsideWholeDocumentScope() throws {
        let commands: [MarkdownInsertionCommand] = [.bulletedList, .numberedList, .taskList]
        let source = "cafe\u{301} 😀\r\nsecond\rthird"
        let selection = NSRange(location: 0, length: (source as NSString).length)
        for command in commands {
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: command, source: source, selection: selection))
            for allowedScope in [true, false] {
                let view = SourceTextView()
                view.focusesOnAttachment = false
                view.allowsMarkdownInsertion = allowedScope
                view.text = source
                view.selectedRange = selection
                XCTAssertFalse(view.applyMarkdownInsertion(plan), "\(command) applied with no attached input view")
                XCTAssertTrue(SourceSelection.sameText(view.text, source), "\(command) changed literal source")
                XCTAssertEqual(view.selectedRange, selection)
                if !allowedScope { XCTAssertTrue(view.makeMarkdownMenu().children.isEmpty) }
            }
        }
    }
}
