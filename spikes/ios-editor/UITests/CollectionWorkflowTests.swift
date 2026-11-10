import XCTest

@MainActor final class CollectionWorkflowTests: XCTestCase {
    private func launch(root: String, fail: Bool = false, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--library-test-root", root] + (fail ? ["--fail-library-save"] : []) + (dark ? ["--dark-mode"] : [])
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
    private func openNewDocument(_ app: XCUIApplication) {
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5))
        create(app, button: "new-document", name: "Day one")
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5))
        app.buttons["show-document-source"].tap()
        XCTAssertTrue(app.textViews["document-source-editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }
    private func waitForSaved(_ app: XCUIApplication) {
        let saved = NSPredicate(format: "label == %@", "Saved on this device")
        expectation(for: saved, evaluatedWith: app.staticTexts["document-save-status"])
        waitForExpectations(timeout: 10)
    }
    func testCreateEditCloseReopenAndRelaunchPreservesExactSource() {
        let root = UUID().uuidString
        var app = launch(root: root)
        openNewDocument(app)
        app.typeText("# Day one\nLiteral -- \"notes\" and café\n")
        let editor = app.textViews["document-source-editor"]
        let source = editor.value as? String
        XCTAssertTrue(source?.contains("Literal -- \"notes\" and café") == true)
        waitForSaved(app)
        app.buttons["close-document"].tap()
        let document = app.buttons["document-Day one.mrk"]
        XCTAssertTrue(document.waitForExistence(timeout: 5)); document.tap()
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5)); app.buttons["show-document-source"].tap()
        XCTAssertEqual(app.textViews["document-source-editor"].value as? String, source)
        // Wait for an acknowledged save before termination; crash recovery is a
        // separate gate and is not inferred from this relaunch scenario.
        waitForSaved(app)
        app.terminate()
        app = launch(root: root)
        XCTAssertTrue(app.buttons["collection-Journal"].waitForExistence(timeout: 5)); app.buttons["collection-Journal"].tap()
        XCTAssertTrue(app.buttons["document-Day one.mrk"].waitForExistence(timeout: 5)); app.buttons["document-Day one.mrk"].tap()
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5)); app.buttons["show-document-source"].tap()
        XCTAssertEqual(app.textViews["document-source-editor"].value as? String, source)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reopened saved native document"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSaveFailureKeepsDocumentOpenAndRetainsEdits() {
        let app = launch(root: UUID().uuidString, fail: true)
        openNewDocument(app)
        app.typeText("Retain these edits")
        let editor = app.textViews["document-source-editor"]
        let source = editor.value as? String
        let failed = NSPredicate(format: "label BEGINSWITH %@", "Could not save.")
        expectation(for: failed, evaluatedWith: app.staticTexts["document-save-status"])
        waitForExpectations(timeout: 10)
        app.buttons["close-document"].tap()
        XCTAssertTrue(app.buttons["retry-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(editor.exists); XCTAssertEqual(editor.value as? String, source)
        app.buttons["retry-save"].tap()
        XCTAssertEqual(editor.value as? String, source)
    }
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let detail = "\(issue.compactDescription)\n\(issue.detailedDescription)\nidentifier: \(element?.identifier ?? "none")\nlabel: \(element?.label ?? "none")\nframe: \(String(describing: element?.frame))"
            let attachment = XCTAttachment(string: detail)
            attachment.name = "Collection audit diagnostic"; attachment.lifetime = .keepAlways; self.add(attachment)
            return false
        }
    }
    func testDarkCollectionAndDocumentListsAccessibilityAudit() throws {
        let app = launch(root: UUID().uuidString, dark: true)
        try audit(app)
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5))
        try audit(app)
        create(app, button: "new-document", name: "Day one")
        XCTAssertTrue(app.buttons["close-document"].waitForExistence(timeout: 5))
        try audit(app)
    }
    func testCollectionAndDocumentListsAccessibilityAudit() throws {
        let app = launch(root: UUID().uuidString)
        try audit(app)
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5))
        try audit(app)
        create(app, button: "new-document", name: "Day one")
        XCTAssertTrue(app.buttons["close-document"].waitForExistence(timeout: 5))
        try audit(app)
    }
}
