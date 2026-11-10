import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Authored compile-only case; attached UIKit and OS input remain unrun.
@MainActor final class NativeSourceSelectionFindTests: XCTestCase {
    func testDetachedAndSeparateWholeDocumentScopesRemainInert() throws {
        let source = "e\u{301} 😀 e\u{301}"
        let selected = NSRange(location: 0, length: 2)
        let plan = try XCTUnwrap(SourceSelectionFind.make(source: source, selection: selected).next)
        for headingAllowed in [false, true] {
            for findAllowed in [false, true] {
                let view = SourceTextView()
                view.focusesOnAttachment = false
                view.allowsHeadingNavigation = headingAllowed
                view.allowsSelectionFind = findAllowed
                view.text = source; view.selectedRange = selected
                XCTAssertFalse(view.applySelectionFind(plan))
                XCTAssertTrue(SourceSelection.sameText(view.text, source))
                XCTAssertEqual(view.selectedRange, selected)
                let menu = view.makeSelectionFindMenu()
                XCTAssertEqual(menu.children.prefix(2).map(\.title), [SourceSelectionFind.nextTitle, SourceSelectionFind.previousTitle])
                XCTAssertTrue(menu.children.compactMap { $0 as? UIAction }.allSatisfy { $0.attributes.contains(.disabled) })
                let coordinator = NativeSourceEditor.Coordinator { _, _, _ in XCTFail("Detached selection find reported a change") }
                view.allowsMarkdownInsertion = false
                let blockMenu = coordinator.textView(view, editMenuForTextIn: selected, suggestedActions: [])
                XCTAssertTrue(blockMenu?.children.isEmpty == true)
                view.allowsMarkdownInsertion = true
                XCTAssertNil(coordinator.textView(view, editMenuForTextIn: .init(location: 1, length: 1), suggestedActions: []))
            }
        }
    }
}
