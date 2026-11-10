import XCTest

@MainActor final class RecoveryWorkflowTests: XCTestCase {
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
    private func failedEdit(_ app: XCUIApplication) -> String {
        create(app, button: "new-collection", name: "Journal")
        XCTAssertTrue(app.buttons["new-document"].waitForExistence(timeout: 5))
        create(app, button: "new-document", name: "Day one")
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5)); app.buttons["show-document-source"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("Recovery -- \"notes\" and café\n")
        let source = app.textViews["document-source-editor"].value as? String ?? "missing"
        XCTAssertTrue(source.contains("Recovery -- \"notes\" and café"))
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "Could not save."), evaluatedWith: app.staticTexts["document-save-status"])
        expectation(for: NSPredicate(format: "label == %@", "Recovery copy saved on this device"), evaluatedWith: app.staticTexts["document-recovery-status"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["close-with-recovery"].waitForExistence(timeout: 5))
        return source
    }
    private func openSource(_ app: XCUIApplication, filename: String) -> XCUIElement {
        let button = app.buttons["document-\(filename)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 5)); app.buttons["show-document-source"].tap()
        let source = app.textViews["document-source-editor"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        return source
    }
    func testTerminationAfterCheckpointRestoresNewCopyWithoutChangingOriginal() {
        let root = UUID().uuidString
        var app = launch(root: root, fail: true)
        let source = failedEdit(app)
        // Terminate only after the durable checkpoint acknowledgement; this does
        // not simulate a power failure or a kill during an unacknowledged write.
        app.terminate()
        app = launch(root: root)
        let recovery = app.buttons["recovery-Day one.mrk"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 5)); recovery.tap()
        let preview = app.textViews["recovered-source"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertEqual(preview.value as? String, source)
        XCTAssertEqual(app.keyboards.count, 0)
        app.buttons["save-recovered-copy"].tap()
        XCTAssertTrue(app.alerts.buttons["Save"].waitForExistence(timeout: 5)); app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["recovery-restored"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Recovered copy confirmation"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["close-recovery"].tap()
        XCTAssertTrue(app.buttons["document-Recovered Day one.mrk"].waitForExistence(timeout: 5))
        XCTAssertFalse(recovery.exists)
        let original = openSource(app, filename: "Day one.mrk")
        XCTAssertEqual(original.value as? String, "")
        app.buttons["close-document"].tap()
        let restored = openSource(app, filename: "Recovered Day one.mrk")
        XCTAssertEqual(restored.value as? String, source)
        app.terminate()
        app = launch(root: root)
        XCTAssertFalse(app.buttons["recovery-Day one.mrk"].exists)
        app.buttons["collection-Journal"].tap()
        XCTAssertTrue(app.buttons["document-Recovered Day one.mrk"].waitForExistence(timeout: 5))
    }
    private func auditRecovery(dark: Bool) throws {
        let app = launch(root: UUID().uuidString, fail: true, dark: dark)
        let source = failedEdit(app)
        app.buttons["close-with-recovery"].tap()
        let recovery = app.buttons["recovery-Day one.mrk"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
        try audit(app)
        recovery.tap()
        XCTAssertTrue(app.textViews["recovered-source"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["recovered-source"].value as? String, source)
        try audit(app)
    }
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let attachment = XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\nidentifier: \(element?.identifier ?? "none")\nlabel: \(element?.label ?? "none")\nframe: \(String(describing: element?.frame))")
            attachment.name = "Recovery audit diagnostic"; attachment.lifetime = .keepAlways; self.add(attachment)
            return false
        }
    }
    func testRecoveryInboxAndPreviewAccessibilityAudit() throws { try auditRecovery(dark: false) }
    func testDarkRecoveryInboxAndPreviewAccessibilityAudit() throws { try auditRecovery(dark: true) }
}
