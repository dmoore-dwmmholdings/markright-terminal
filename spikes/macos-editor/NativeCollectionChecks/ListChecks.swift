import AppKit
import Foundation
import SwiftUI

private struct ListCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func listRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ListCheckFailure(message) }
}

@MainActor private func listWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw ListCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func listFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = listFind(child) { return text } }
    return nil
}

@MainActor private final class ListUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor private func listChoose(_ command: MarkdownInsertionCommand, text: MacSourceTextView) throws {
    let menu = text.makeMarkdownMenu()
    guard let index = menu.items.firstIndex(where: { $0.title == command.title }), menu.items[index].isEnabled else {
        throw ListCheckFailure("Enabled list command missing: " + command.title)
    }
    menu.performActionForItem(at: index)
}

/// Real native menu targets and undo; no visible menu, synthetic OS event,
/// app activation, source-file access or real collection-root operation.
@MainActor func runMarkdownListChecks() async throws {
    for command in [MarkdownInsertionCommand.bulletedList, .numberedList, .taskList] {
        let source = "\u{FEFF}one 😀\r\n\r\ntwo Cafe\u{301}\rthree\n"
        let markers: [String]
        switch command {
        case .bulletedList: markers = ["- ", "- ", "- "]
        case .numberedList: markers = ["1. ", "2. ", "3. "]
        case .taskList: markers = ["- [ ] ", "- [ ] ", "- [ ] "]
        default: throw ListCheckFailure("Unexpected list command")
        }
        let expected = "\u{FEFF}" + markers[0] + "one 😀\r\n\r\n" + markers[1] + "two Cafe\u{301}\r" + markers[2] + "three\n"
        var reported = source
        var reportedRange = SourceSelection.beginning
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let undoDelegate = ListUndoDelegate()
        undoDelegate.manager.groupsByEvent = false
        window.delegate = undoDelegate
        let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: SourceSelection.beginning, isEditable: true) {
            reported = $0; reportedRange = $2
        })
        window.contentView = host
        defer {
            if let text = listFind(host) { text.onTextStateChanged = nil; text.delegate = nil }
            window.makeFirstResponder(nil)
            undoDelegate.manager.removeAllActions()
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
        try await listWait("native list source attachment") { host.layoutSubtreeIfNeeded(); return listFind(host) != nil }
        guard let text = listFind(host) else { throw ListCheckFailure("Native list source missing") }
        try listRequire(window.makeFirstResponder(text), "Native list source focus unavailable")
        text.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
        try listChoose(command, text: text)
        try listRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                        "List menu changed BOM/row text/physical endings or failed to report source")
        try listRequire(text.selectedRange() == NSRange(location: 1, length: expected.utf16.count - 1) &&
            reportedRange == text.selectedRange() && window.firstResponder === text,
            "List menu failed to select transformed content or moved focus")
        try listRequire(undoDelegate.manager.canUndo, "List insertion lacks native undo")
        undoDelegate.manager.undo()
        try listRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source),
                        "List undo failed to restore exact original bytes")
        undoDelegate.manager.redo()
        try listRequire(SourceSelection.sameText(text.string, expected), "List redo lost marker/blank-row bytes")
        undoDelegate.manager.undo()
        text.setSelectedRange(NSRange(location: 1, length: 0))
        try listChoose(command, text: text)
        let prefixed = "\u{FEFF}" + markers[0] + (source as NSString).substring(from: 1)
        try listRequire(SourceSelection.sameText(text.string, prefixed) &&
            text.selectedRange() == NSRange(location: 1 + markers[0].utf16.count, length: 0),
            "Existing-line caret did not insert only its marker after BOM")
        undoDelegate.manager.undo()
        text.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        try listChoose(command, text: text)
        let placeholder = source + markers[0] + "item"
        try listRequire(SourceSelection.sameText(text.string, placeholder) &&
            text.selectedRange() == NSRange(location: source.utf16.count + markers[0].utf16.count, length: 4),
            "Empty-line list starter did not select its item placeholder")
        undoDelegate.manager.beginUndoGrouping()
        text.insertText("new entry", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoDelegate.manager.endUndoGrouping()
        try listRequire(SourceSelection.sameText(text.string, source + markers[0] + "new entry"),
                        "List placeholder typing changed another row")
        undoDelegate.manager.undo()
        try listRequire(SourceSelection.sameText(text.string, placeholder), "List typing undo lost its starter")
        undoDelegate.manager.undo()
        try listRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source),
                        "List starter undo failed to restore original source")
        text.setSelectedRange(NSRange(location: 2, length: 2))
        let invalidMenu = text.makeMarkdownMenu()
        guard let invalidItem = invalidMenu.items.first(where: { $0.title == command.title }) else {
            throw ListCheckFailure("Refused partial-line command disappeared")
        }
        try listRequire(!invalidItem.isEnabled && SourceSelection.sameText(text.string, source),
                        "Partial-line list selection was enabled or changed source")
        try listRequire(!window.isVisible && !NSApplication.shared.isActive, "List probe showed or activated a window")
    }
    print("PASS native list source: real bullet/number/task menu actions, literal BOM/NFD/emoji/mixed endings and blank rows, whole-content selection, native undo/redo, existing-line marker caret and separately undoable placeholder typing; partial-line refusal")
    print("Passed 1 native list AppKit group. Authored actions only; actual OS menus/keyboard/IME, iOS runtime, semantic list rendering and release remain open.")
}
