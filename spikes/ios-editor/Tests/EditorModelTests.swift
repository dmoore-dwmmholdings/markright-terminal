import XCTest
@testable import MarkrightEditorSpike
@MainActor final class EditorModelTests: XCTestCase {
    func testSourceRoundTripAndAtomicBlocks() {
        let source = "# title\n\n```swift\nx=1\n```\n|a|b|\n|-|-|\n|x|y|\n😀\n"
        let m = EditorModel(source: source)
        XCTAssertEqual(m.source, source)
        XCTAssertEqual(m.blocks.filter(\.atomic).count, 2)
    }
    func testCompositionPreventsSwitchingOrPreviewReplacement() {
        let m = EditorModel(source: "one\ntwo"); m.activate(0); m.composing = true
        m.activate(1); m.finish(); XCTAssertEqual(m.active, 0)
        m.update(0,"日本語"); XCTAssertEqual(m.source,"日本語\ntwo")
        m.composing = false; m.finish(); XCTAssertNil(m.active)
    }
    func testEditingOneBlockPreservesAdjacentSource() {
        let m = EditorModel(source: "first\n**middle**\nlast")
        m.update(1, "😀 edited\nnew line")
        XCTAssertEqual(m.source,"first\n😀 edited\nnew line\nlast")
    }
}
