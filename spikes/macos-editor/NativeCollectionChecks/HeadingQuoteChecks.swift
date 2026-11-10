import AppKit
import Foundation
import SwiftUI

private struct HeadingQuoteCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func headingQuoteRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw HeadingQuoteCheckFailure(message) }
}

@MainActor private func headingQuoteWait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw HeadingQuoteCheckFailure("Timed out attaching heading/quote source") }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func headingQuoteFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = headingQuoteFind(child) { return text } }
    return nil
}

@MainActor private final class HeadingQuoteUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor private func headingQuoteChoose(_ command: MarkdownInsertionCommand, text: MacSourceTextView) throws {
    let menu = text.makeMarkdownMenu()
    guard let index = menu.items.firstIndex(where: { $0.title == command.title }), menu.items[index].isEnabled else {
        throw HeadingQuoteCheckFailure("Enabled heading/quote command missing: " + command.title)
    }
    menu.performActionForItem(at: index)
}

/// Authored native menu targets and undo only. Never shows or activates the
/// window, sends OS input, accesses a source file or opens a collection root.
@MainActor func runMarkdownHeadingQuoteChecks() async throws {
    for (command, marker, placeholder) in [
        (MarkdownInsertionCommand.heading1, "# ", "heading"), (.heading2, "## ", "heading"),
        (.heading3, "### ", "heading"), (.blockquote, "> ", "text")
    ] {
        let source = "\u{FEFF}\r\none 😀\r\n \t\rtwo Cafe\u{301}\n\n"
        let blankMarker = command == .blockquote ? marker : ""
        let expected = "\u{FEFF}" + blankMarker + "\r\n" + marker + "one 😀\r\n" + blankMarker + " \t\r"
            + marker + "two Cafe\u{301}\n" + blankMarker + "\n"
        var reported = source
        var reportedRange = SourceSelection.beginning
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let undoDelegate = HeadingQuoteUndoDelegate()
        undoDelegate.manager.groupsByEvent = false
        window.delegate = undoDelegate
        let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: SourceSelection.beginning, isEditable: true) {
            reported = $0; reportedRange = $2
        })
        window.contentView = host
        defer {
            if let text = headingQuoteFind(host) { text.onTextStateChanged = nil; text.delegate = nil }
            window.makeFirstResponder(nil)
            undoDelegate.manager.removeAllActions()
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
        try await headingQuoteWait { host.layoutSubtreeIfNeeded(); return headingQuoteFind(host) != nil }
        guard let text = headingQuoteFind(host) else { throw HeadingQuoteCheckFailure("Native heading/quote source missing") }
        try headingQuoteRequire(window.makeFirstResponder(text), "Native heading/quote source focus unavailable")
        text.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
        try headingQuoteChoose(command, text: text)
        try headingQuoteRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                                "Heading/quote menu changed BOM/row text/endings or failed to report source")
        try headingQuoteRequire(text.selectedRange() == NSRange(location: 1, length: expected.utf16.count - 1) &&
            reportedRange == text.selectedRange() && window.firstResponder === text,
            "Heading/quote menu lost transformed selection or focus")
        try headingQuoteRequire(undoDelegate.manager.canUndo, "Heading/quote insertion lacks native undo")
        undoDelegate.manager.undo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source),
                                "Heading/quote undo failed to restore exact bytes")
        undoDelegate.manager.redo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                                "Heading/quote redo lost literal prefix/blank-row bytes")
        undoDelegate.manager.undo()

        // The first content row begins after BOM plus its original CRLF.
        let contentStart = "\u{FEFF}\r\n".utf16.count
        text.setSelectedRange(NSRange(location: contentStart, length: 0))
        try headingQuoteChoose(command, text: text)
        let prefixed = (source as NSString).substring(to: contentStart) + marker + (source as NSString).substring(from: contentStart)
        try headingQuoteRequire(SourceSelection.sameText(text.string, prefixed) &&
            text.selectedRange() == NSRange(location: contentStart + marker.utf16.count, length: 0),
            "Nonblank row caret did not insert only its marker")
        undoDelegate.manager.undo()

        // Blank caret immediately after BOM; original first-row CRLF remains.
        text.setSelectedRange(NSRange(location: 1, length: 0))
        try headingQuoteChoose(command, text: text)
        let starter = "\u{FEFF}" + marker + placeholder + (source as NSString).substring(from: 1)
        let typed = "\u{FEFF}" + marker + "new content" + (source as NSString).substring(from: 1)
        try headingQuoteRequire(SourceSelection.sameText(text.string, starter) &&
            text.selectedRange() == NSRange(location: 1 + marker.utf16.count, length: placeholder.utf16.count) &&
            reportedRange == text.selectedRange(), "Blank heading/quote row did not select its exact placeholder after BOM")
        undoDelegate.manager.beginUndoGrouping()
        text.insertText("new content", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoDelegate.manager.endUndoGrouping()
        try headingQuoteRequire(SourceSelection.sameText(text.string, typed) && SourceSelection.sameText(reported, typed),
                                "Heading/quote placeholder typing changed other bytes")
        undoDelegate.manager.undo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, starter), "Typing undo lost heading/quote starter")
        undoDelegate.manager.undo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source),
                                "Starter undo did not restore original source")
        undoDelegate.manager.redo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, starter), "Starter redo changed original row bytes")
        undoDelegate.manager.redo()
        try headingQuoteRequire(SourceSelection.sameText(text.string, typed), "Typing redo lost heading/quote body")
        undoDelegate.manager.undo()
        undoDelegate.manager.undo()

        text.setSelectedRange(NSRange(location: contentStart, length: 0))
        let capturedMenu = text.makeMarkdownMenu()
        guard let capturedIndex = capturedMenu.items.firstIndex(where: { $0.title == command.title }),
              capturedMenu.items[capturedIndex].isEnabled else {
            throw HeadingQuoteCheckFailure("Fresh heading/quote action missing before stale-caret check")
        }
        text.setSelectedRange(NSRange(location: contentStart + 1, length: 2))
        capturedMenu.performActionForItem(at: capturedIndex)
        try headingQuoteRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source) &&
            text.selectedRange() == NSRange(location: contentStart + 1, length: 2),
            "Retained heading/quote menu applied after the captured selection changed")
        let invalidMenu = text.makeMarkdownMenu()
        guard let invalidItem = invalidMenu.items.first(where: { $0.title == command.title }) else {
            throw HeadingQuoteCheckFailure("Refused partial-row command disappeared")
        }
        try headingQuoteRequire(!invalidItem.isEnabled && SourceSelection.sameText(text.string, source),
                                "Partial-row heading/quote command was enabled or changed source")
        try headingQuoteRequire(!window.isVisible && !NSApplication.shared.isActive, "Heading/quote check showed or activated a window")
    }
    print("PASS native heading/quote source: real Heading 1/2/3 and Blockquote menu actions, literal BOM/NFD/emoji/mixed endings, selected quote blank rows, transformed selection, marker-only caret, selected placeholders, separate typing/insertion undo and redo; stale-caret and partial-row refusal")
    print("Passed 1 native heading/quote AppKit group. Authored actions only; actual OS menus/keyboard/IME, iOS runtime, VoiceOver, full authoring and release remain open.")
}
