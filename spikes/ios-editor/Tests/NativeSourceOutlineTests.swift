import XCTest
import UIKit
@testable import MarkrightEditorSpike

/// Compile-only until an authorized simulator/device run is available.
/// Detached refusal is not proof of attached menu/selection/undo behavior.
@MainActor final class NativeSourceOutlineTests: XCTestCase {
    func testDetachedOrOutsideWholeDocumentNavigationRemainsInert() throws {
        let source = "\u{FEFF}# Cafe\u{301} 😀\r\n## Destination\n"
        let report = SourceOutline.make(source: source)
        let range = NSRange(location: 1, length: 0)
        let plan = try XCTUnwrap(report.plan(for: report.headings[1], selection: range))
        for allowed in [false, true] {
            let view = SourceTextView()
            view.focusesOnAttachment = false
            view.allowsHeadingNavigation = allowed
            view.text = source
            view.selectedRange = range
            XCTAssertFalse(view.applyHeadingNavigation(plan))
            XCTAssertTrue(SourceSelection.sameText(view.text, source))
            XCTAssertEqual(view.selectedRange, range)
            let menu = view.makeOutlineMenu()
            XCTAssertEqual(menu.children.count, 1)
            let status = try XCTUnwrap(menu.children.first as? UIAction)
            XCTAssertTrue(status.attributes.contains(.disabled))
        }
    }
}
