import XCTest
@MainActor final class EditorInteractionTests: XCTestCase {
    func testActiveLineAndAtomicFenceTransition() {
        let app = XCUIApplication(); app.launch()
        let line = app.buttons["preview-1"]
        XCTAssertTrue(line.waitForExistence(timeout: 10)); line.tap()
        let editor = app.textViews["source-editor-1"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Native **preview** example")
        XCTAssertTrue(app.buttons["preview-0"].exists)
        editor.tap(); editor.typeText(" changed -- \"quoted\"")
        let editedSource = editor.value as? String
        XCTAssertTrue(editedSource?.contains(" changed -- \"quoted\"") == true)
        app.buttons["finish-editing"].tap()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["preview-0"].label, "# Markright Terminal")
        app.buttons["preview-1"].tap()
        XCTAssertEqual(app.textViews["source-editor-1"].value as? String, editedSource)
        app.buttons["finish-editing"].tap()
        app.buttons["preview-3"].tap()
        XCTAssertTrue(app.textViews["source-editor-3"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["source-editor-3"].value as? String ?? "").contains("let value = 42"))
    }
    func testLargeDocumentCanEnterEditAndReturnToPreview() {
        let app = XCUIApplication(); app.launchArguments = ["--large-document"]; app.launch()
        let first = app.buttons["preview-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 20)); first.tap()
        let editor = app.textViews["source-editor-0"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("typed")
        let source = editor.value as? String
        XCTAssertTrue(source?.contains("typed") == true)
        app.buttons["finish-editing"].tap(); app.buttons["preview-0"].tap()
        XCTAssertEqual(app.textViews["source-editor-0"].value as? String, source)
    }

}
