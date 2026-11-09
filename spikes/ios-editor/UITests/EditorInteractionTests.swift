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
    func testWholeDocumentSourceCanEditAndReturnWithoutLosingMarkdown() {
        let app = XCUIApplication(); app.launch()
        let sourceButton = app.buttons["show-document-source"]
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 10)); sourceButton.tap()
        let editor = app.textViews["document-source-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let original = editor.value as? String ?? ""
        XCTAssertTrue(original.contains("# Markright Terminal\nNative **preview** example"))
        XCTAssertTrue(original.contains("```swift\nlet value = 42\n```"))
        XCTAssertTrue(original.contains("| Field | Value |"))
        editor.tap(); editor.typeText(" literal -- \"source\" ")
        let changed = editor.value as? String ?? ""
        XCTAssertTrue(changed.contains(" literal -- \"source\" "))
        XCTAssertEqual(changed.replacingOccurrences(of: " literal -- \"source\" ", with: ""), original)
        app.buttons["finish-editing"].tap()
        XCTAssertTrue(app.buttons["preview-0"].waitForExistence(timeout: 5))
        sourceButton.tap()
        XCTAssertEqual(app.textViews["document-source-editor"].value as? String, changed)
    }
    func testStaticCalculatorResultRemainsReadableWithoutExecution() {
        let app = XCUIApplication(); app.launchArguments = ["--static-calculator"]; app.launch()
        let warning = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "execution is unavailable")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "18446744073709551615")).firstMatch
        XCTAssertTrue(result.exists)
        XCTAssertTrue(result.label.contains("| Value | 18446744073709551615 |"))
        app.buttons["show-document-source"].tap()
        let source = app.textViews["document-source-editor"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let text = source.value as? String ?? ""
        XCTAssertTrue(text.contains("18446744073709551615"))
        XCTAssertTrue(text.contains("throw new Error(\"snapshot-executed\");"))
        XCTAssertTrue(text.contains("No freshness or trust verification is claimed."))
    }

    func testPreviewAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: .all)
    }

    func testDarkPreviewAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--dark-mode"]; app.launch()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: .all)
    }

}
