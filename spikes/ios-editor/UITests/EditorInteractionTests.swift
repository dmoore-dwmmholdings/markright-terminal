import XCTest
import Vision
@MainActor final class EditorInteractionTests: XCTestCase {
    func testBlockCaretResumesAfterReadingWithoutTappingTheEditor() {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 10)); app.buttons["preview-1"].tap()
        let editor = app.textViews["source-editor-1"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("CARET")
        let before = editor.value as? String ?? ""
        XCTAssertTrue(before.hasPrefix("CARET"))
        app.buttons["toggle-reading-mode"].tap(); app.buttons["toggle-reading-mode"].tap()
        app.buttons["preview-1"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, before.replacingOccurrences(of: "CARET", with: "CARETX"))
    }
    func testWholeSourceCaretResumesAfterReadingWithoutTappingTheEditor() {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 10)); app.buttons["show-document-source"].tap()
        let editor = app.textViews["document-source-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("CARET")
        let before = editor.value as? String ?? ""
        XCTAssertTrue(before.hasPrefix("CARET"))
        app.buttons["toggle-reading-mode"].tap(); app.buttons["toggle-reading-mode"].tap()
        app.buttons["show-document-source"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("X")
        XCTAssertEqual(editor.value as? String, before.replacingOccurrences(of: "CARET", with: "CARETX"))
    }
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let detail = "\(issue.compactDescription)\n\(issue.detailedDescription)\nidentifier: \(element?.identifier ?? "none")\nlabel: \(element?.label ?? "none")\nframe: \(String(describing: element?.frame))"
            let attachment = XCTAttachment(string: detail)
            attachment.name = "Audit element diagnostic"; attachment.lifetime = .keepAlways; self.add(attachment)
            return false // Report every issue; no category or element is ignored.
        }
    }
    func testReadingModeShowsStaticTextAndPreservesEditsOnExit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        let preview = app.buttons["preview-1"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); preview.tap()
        let editor = app.textViews["source-editor-1"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(" literal -- \"read\" ")
        let edited = editor.value as? String
        let reading = app.buttons["toggle-reading-mode"]
        reading.tap()
        let text = app.staticTexts["reading-1"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        // Markdown presentation trims leading whitespace; raw source is checked
        // exactly after leaving reading mode below.
        XCTAssertTrue(text.label.contains("literal -- \"read\""), "Reading label: \(text.label); edited source: \(edited ?? "missing")")
        XCTAssertFalse(app.buttons["preview-1"].exists)
        XCTAssertFalse(app.buttons["show-document-source"].exists)
        XCTAssertFalse(app.buttons["finish-editing"].exists)
        XCTAssertEqual(reading.value as? String, "On")
        // Capture evidence after keyboard dismissal and the button label's
        // native transition, rather than recording an intermediate frame.
        Thread.sleep(forTimeInterval: 0.75)
        let rendered = app.screenshot()
        let caption = VNRecognizeTextRequest()
        caption.recognitionLevel = .accurate
        caption.recognitionLanguages = ["en-US"]
        caption.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(rendered.image.cgImage)).perform([caption])
        let visibleText = caption.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        XCTAssertTrue(visibleText.contains("Exit reading"), "Missing rendered mode caption: \(visibleText)")
        let screenshot = XCTAttachment(screenshot: rendered)
        screenshot.name = "Native reading mode"; screenshot.lifetime = .keepAlways; add(screenshot)
        text.tap()
        XCTAssertEqual(app.textViews.count, 0)
        reading.tap()
        XCTAssertEqual(reading.value as? String, "Off")
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); preview.tap()
        XCTAssertEqual(app.textViews["source-editor-1"].value as? String, edited)
    }
    func testReadingModeCommitsWholeSourceBeforeShowingStaticText() {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["show-document-source"].waitForExistence(timeout: 10))
        app.buttons["show-document-source"].tap()
        let editor = app.textViews["document-source-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(" literal source ")
        let edited = editor.value as? String
        let reading = app.buttons["toggle-reading-mode"]; reading.tap()
        XCTAssertTrue(app.staticTexts["reading-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews.count, 0)
        reading.tap(); app.buttons["show-document-source"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertEqual(editor.value as? String, edited)
    }
    func testReadingAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["toggle-reading-mode"].waitForExistence(timeout: 10))
        app.buttons["toggle-reading-mode"].tap()
        XCTAssertTrue(app.staticTexts["reading-1"].waitForExistence(timeout: 5))
        try audit(app)
    }
    func testDarkReadingAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture", "--dark-mode"]; app.launch()
        XCTAssertTrue(app.buttons["toggle-reading-mode"].waitForExistence(timeout: 10))
        app.buttons["toggle-reading-mode"].tap()
        XCTAssertTrue(app.staticTexts["reading-1"].waitForExistence(timeout: 5))
        try audit(app)
    }
    func testActiveLineAndAtomicFenceTransition() {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
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
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture", "--large-document"]; app.launch()
        let first = app.buttons["preview-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 20)); first.tap()
        let editor = app.textViews["source-editor-0"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("typed")
        let source = editor.value as? String
        XCTAssertTrue(source?.contains("typed") == true)
        app.buttons["finish-editing"].tap(); app.buttons["preview-0"].tap()
        XCTAssertEqual(app.textViews["source-editor-0"].value as? String, source)
        app.buttons["toggle-reading-mode"].tap()
        XCTAssertTrue(app.staticTexts["reading-0"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.textViews.count, 0)
        app.buttons["toggle-reading-mode"].tap(); app.buttons["preview-0"].tap()
        XCTAssertEqual(app.textViews["source-editor-0"].value as? String, source)
    }
    func testWholeDocumentSourceCanEditAndReturnWithoutLosingMarkdown() {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
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
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture", "--static-calculator"]; app.launch()
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
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 10))
        try audit(app)
    }

    func testDarkPreviewAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--editor-fixture", "--dark-mode"]; app.launch()
        XCTAssertTrue(app.buttons["preview-1"].waitForExistence(timeout: 10))
        try audit(app)
    }

}
