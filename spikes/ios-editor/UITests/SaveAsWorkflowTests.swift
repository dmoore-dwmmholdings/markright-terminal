import XCTest

@MainActor final class SaveAsWorkflowTests: XCTestCase {
    private func launch(root: String, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library-test-root", root] + (dark ? ["--dark-mode"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["new-collection"].waitForExistence(timeout: 10))
        return app
    }
    private func create(_ app: XCUIApplication, button: String, name: String) {
        app.buttons[button].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        app.alerts.buttons["Create"].tap()
    }
    private func newDocument(_ app: XCUIApplication) {
        create(app, button: "new-document", name: "Day one")
        XCTAssertTrue(app.buttons["save-as-document"].waitForExistence(timeout: 5))
    }
    private func source(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5)); app.buttons["show-document-source"].tap()
        let editor = app.textViews["document-source-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        return editor
    }
    private func saved(_ app: XCUIApplication) {
        expectation(for: NSPredicate(format: "label == %@", "Saved on this device"), evaluatedWith: app.staticTexts["document-save-status"])
        waitForExpectations(timeout: 10)
    }
    private func open(_ app: XCUIApplication, filename: String) -> XCUIElement {
        XCTAssertTrue(app.buttons["document-\(filename)"].waitForExistence(timeout: 5)); app.buttons["document-\(filename)"].tap()
        return source(app)
    }
    func testSaveAsAcrossCollectionsResumesCaretAndPersistsOnlyNewDestinationEdits() {
        let root = UUID().uuidString
        var app = launch(root: root)
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-collection"].waitForExistence(timeout: 5))
        create(app, button: "new-collection", name: "Archive")
        XCTAssertTrue(app.buttons["collection-Journal"].waitForExistence(timeout: 5)); app.buttons["collection-Journal"].tap()
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5)); newDocument(app)
        let editor = source(app)
        app.typeText("CARET literal -- \"notes\" and café\n")
        let original = editor.value as? String ?? "missing"
        saved(app)
        app.buttons["save-as-document"].tap()
        XCTAssertTrue(app.buttons["save-as-collection-Archive"].waitForExistence(timeout: 5)); app.buttons["save-as-collection-Archive"].tap()
        app.buttons["confirm-save-as"].tap()
        XCTAssertTrue(app.staticTexts["Day one copy.mrk"].waitForExistence(timeout: 10))
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // No editor tap: the naming sheet must resume the saved caret itself.
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, original + "X")
        saved(app); app.buttons["close-document"].tap()
        XCTAssertTrue(app.buttons["document-Day one copy.mrk"].waitForExistence(timeout: 5))
        XCTAssertEqual(open(app, filename: "Day one copy.mrk").value as? String, original + "X")
        app.buttons["close-document"].tap()
        XCTAssertTrue(app.buttons["collection-Journal"].waitForExistence(timeout: 5)); app.buttons["collection-Journal"].tap()
        XCTAssertEqual(open(app, filename: "Day one.mrk").value as? String, original)
        app.terminate()
        app = launch(root: root)
        app.buttons["collection-Archive"].tap()
        XCTAssertEqual(open(app, filename: "Day one copy.mrk").value as? String, original + "X")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reopened Save As destination"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCollisionKeepsNamingSheetAndCancelResumesOriginalCaret() {
        let app = launch(root: UUID().uuidString)
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5)); newDocument(app)
        let editor = source(app); app.typeText("CARET"); saved(app)
        app.buttons["save-as-document"].tap()
        XCTAssertTrue(app.buttons["clear-save-as-name"].waitForExistence(timeout: 5)); app.buttons["clear-save-as-name"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "save-as-name").firstMatch
        field.tap(); app.typeText("Day one")
        app.buttons["confirm-save-as"].tap()
        XCTAssertTrue(app.staticTexts["save-as-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["cancel-save-as"].exists); app.buttons["cancel-save-as"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, "CARETX")
        saved(app); app.buttons["close-document"].tap()
        XCTAssertTrue(app.buttons["document-Day one.mrk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["document-Day one copy.mrk"].exists)
    }
    private func auditSaveAs(dark: Bool) throws {
        let app = launch(root: UUID().uuidString, dark: dark)
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5)); newDocument(app)
        app.buttons["save-as-document"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "save-as-name").firstMatch.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let detail = "\(issue.compactDescription)\n\(issue.detailedDescription)\nidentifier: \(element?.identifier ?? "none")\nlabel: \(element?.label ?? "none")\nframe: \(String(describing: element?.frame))"
            let attachment = XCTAttachment(string: detail)
            attachment.name = "Save As audit diagnostic"; attachment.lifetime = .keepAlways; self.add(attachment)
            return false
        }
    }
    func testSaveAsAccessibilityAudit() throws { try auditSaveAs(dark: false) }
    func testDarkSaveAsAccessibilityAudit() throws { try auditSaveAs(dark: true) }
}
