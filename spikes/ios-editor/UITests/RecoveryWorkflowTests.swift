import XCTest

@MainActor final class RecoveryWorkflowTests: XCTestCase {
    private enum PreconditionFailure: Error { case failed(String) }
    private let typedSource = "Recovery -- \"notes\" and café\n"

    private func require(_ condition: Bool, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            XCTFail(message, file: file, line: line)
            throw PreconditionFailure.failed(message)
        }
    }

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
    private func prepareFailedEdit(_ app: XCUIApplication) throws {
        create(app, button: "new-collection", name: "Journal")
        try require(app.buttons["new-document"].waitForExistence(timeout: 5), "New document action is missing")
        create(app, button: "new-document", name: "Day one")
        try require(app.buttons["show-document-source"].waitForExistence(timeout: 5), "Source action is missing")
        app.buttons["show-document-source"].tap()
        try require(app.textViews["document-source-editor"].waitForExistence(timeout: 5), "Source editor is missing")
        try require(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Source keyboard is missing")
    }

    private func attachInputDiagnostic(_ app: XCUIApplication, phase: String) {
        let editor = app.textViews["document-source-editor"]
        let exists = editor.exists
        let value = exists ? editor.value as? String : nil
        let saveStatus = app.staticTexts["document-save-status"]
        let recoveryStatus = app.staticTexts["document-recovery-status"]
        let attachment = XCTAttachment(string: """
        phase: \(phase)
        editor exists: \(exists)
        editor hittable: \(exists && editor.isHittable)
        editor value: \(String(reflecting: value))
        editor UTF-8: \(String(describing: value.map { Array($0.utf8) }))
        keyboards: \(app.keyboards.count)
        save status: \(saveStatus.exists ? saveStatus.label : "missing")
        recovery status: \(recoveryStatus.exists ? recoveryStatus.label : "missing")
        recovery close exists: \(app.buttons["close-with-recovery"].exists)
        """)
        attachment.name = "Recovery input \(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForExactSource(_ app: XCUIApplication, expected: String, phase: String) throws -> String {
        attachInputDiagnostic(app, phase: "\(phase) immediately after typing")
        let editor = app.textViews["document-source-editor"]
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: editor)
        let result = XCTWaiter.wait(for: [complete], timeout: 5)
        attachInputDiagnostic(app, phase: "\(phase) after exact-source wait")
        try require(result == .completed, "The complete typed source was not visible within 5 seconds")
        let source = editor.value as? String
        try require(source.map { $0.utf8.elementsEqual(expected.utf8) } == true,
                    "The editor source does not exactly match the typed UTF-8")
        return source!
    }

    private func waitForFailedCheckpoint(_ app: XCUIApplication, expected: String) throws {
        let failure = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Could not save."),
                                                object: app.staticTexts["document-save-status"])
        let checkpoint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Recovery copy saved on this device"),
                                                   object: app.staticTexts["document-recovery-status"])
        let result = XCTWaiter.wait(for: [failure, checkpoint], timeout: 10)
        attachInputDiagnostic(app, phase: "after checkpoint acknowledgement wait")
        try require(result == .completed, "Save failure and current recovery checkpoint were not acknowledged within 10 seconds")
        try require(app.buttons["close-with-recovery"].waitForExistence(timeout: 5), "Current recovery close is unavailable")
        let source = app.textViews["document-source-editor"].value as? String
        try require(source.map { $0.utf8.elementsEqual(expected.utf8) } == true,
                    "Source changed before the current checkpoint was acknowledged")
    }

    private func failedEdit(_ app: XCUIApplication) throws -> String {
        try prepareFailedEdit(app)
        app.typeText(typedSource)
        let source = try waitForExactSource(app, expected: typedSource, phase: "complete input")
        try waitForFailedCheckpoint(app, expected: source)
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
    func testTerminationAfterCheckpointRestoresNewCopyWithoutChangingOriginal() throws {
        let root = UUID().uuidString
        var app = launch(root: root, fail: true)
        let source = try failedEdit(app)
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
    func testTypingContinuesWithoutRefocusAfterSaveFailureHeaderAppears() throws {
        let app = launch(root: UUID().uuidString, fail: true)
        try prepareFailedEdit(app)
        app.typeText("Re")
        _ = try waitForExactSource(app, expected: "Re", phase: "prefix input")
        try waitForFailedCheckpoint(app, expected: "Re")
        let editor = app.textViews["document-source-editor"]
        try require(editor.exists && app.keyboards.firstMatch.exists,
                    "Save-failure header removed the source editor or keyboard")
        // No tap or refocus: the status/header transition must preserve input.
        app.typeText("covery -- \"notes\" and café\n")
        let source = try waitForExactSource(app, expected: typedSource, phase: "suffix input")
        try waitForFailedCheckpoint(app, expected: source)
        try require(editor.exists && app.keyboards.firstMatch.exists,
                    "Continued typing lost the source editor or keyboard")
    }
    private func auditRecovery(dark: Bool) throws {
        let app = launch(root: UUID().uuidString, fail: true, dark: dark)
        let source = try failedEdit(app)
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
