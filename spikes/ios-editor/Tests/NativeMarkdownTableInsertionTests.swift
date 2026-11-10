import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Compile-only UIKit coverage until the native shard runs on an available
/// simulator/device; native table-menu and undo interaction remain unverified.
@MainActor final class NativeMarkdownTableInsertionTests: XCTestCase {
    func testValidGridAndStarterPlansStayInertWhenDetachedOrOutsideWholeDocumentScope() throws {
        let fixtures = ["Name\tValue\r\ncafe\u{301}\t😀", ""]
        for source in fixtures {
            let selection = NSRange(location: 0, length: (source as NSString).length)
            let plan = try XCTUnwrap(MarkdownInsertionPlan.make(command: .table, source: source, selection: selection))
            for allowedScope in [true, false] {
                let view = SourceTextView()
                view.focusesOnAttachment = false
                view.allowsMarkdownInsertion = allowedScope
                view.text = source
                view.selectedRange = selection
                XCTAssertFalse(view.applyMarkdownInsertion(plan), "Table insertion applied with no attached input view")
                XCTAssertTrue(SourceSelection.sameText(view.text, source), "Table insertion changed literal source")
                XCTAssertEqual(view.selectedRange, selection)
                if !allowedScope { XCTAssertTrue(view.makeMarkdownMenu().children.isEmpty) }
            }
        }
    }
}
