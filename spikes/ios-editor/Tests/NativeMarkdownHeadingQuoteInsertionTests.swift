import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Authored for compile-only UIKit coverage. No build or runtime evidence is
/// established until the coordinating verification stages actually run.
@MainActor final class NativeMarkdownHeadingQuoteInsertionTests: XCTestCase {
    func testValidHeadingQuotePlansStayInertWhenDetachedOrOutsideWholeDocumentScope() throws {
        let source = "\u{FEFF}cafe\u{301} 😀\r\n\rsecond\n"
        let selection = NSRange(location: 0, length: source.utf16.count)
        for command in [MarkdownInsertionCommand.heading1, .heading2, .heading3, .blockquote] {
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
                if allowedScope {
                    let action = try XCTUnwrap(view.makeMarkdownMenu().children.compactMap { $0 as? UIAction }.first { $0.title == command.title })
                    XCTAssertTrue(action.attributes.contains(.disabled))
                } else {
                    XCTAssertTrue(view.makeMarkdownMenu().children.isEmpty)
                }
            }
        }
    }
}
