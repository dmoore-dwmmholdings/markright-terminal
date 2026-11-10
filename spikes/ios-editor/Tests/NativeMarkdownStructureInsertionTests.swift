import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Focused UIKit refusal contracts. These tests are compile-only
/// evidence until the native shard runs on an available simulator or device.
@MainActor final class NativeMarkdownStructureInsertionTests: XCTestCase {
    private let commands: [MarkdownInsertionCommand] = [.link, .imageReference, .codeBlock]

    func testNewValidPlansStayInertWhenDetachedOrOutsideWholeDocumentScope() throws {
        for command in commands {
            let source = command == .codeBlock ? "cafe\u{301} 😀\r\nline\rnext\n" : "cafe\u{301} 😀"
            let selection = NSRange(location: 0, length: (source as NSString).length)
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
