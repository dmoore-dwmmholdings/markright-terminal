import AppKit
import Foundation
import SwiftUI

private struct StructureCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func structureRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw StructureCheckFailure(message) }
}

@MainActor private func structureWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw StructureCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func structureFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = structureFind(child) { return text } }
    return nil
}

@MainActor private final class StructureUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

private func structureStage(_ message: String) {
    FileHandle.standardError.write(Data("[StructureChecks] \(message)\n".utf8))
}

/// Exercises real native source menu targets without showing a context menu,
/// activating the app, reading files, using a pasteboard or sending OS input.
@MainActor func runMarkdownStructureChecks() async throws {
    for command in [MarkdownInsertionCommand.link, .imageReference, .codeBlock] {
        structureStage(command.title + " host starting")
        let prefix = "\u{FEFF}before\r\n"
        let body = command == .codeBlock ? "let ticks = ```\r\nCafe\u{301} 😀\r" : "Cafe\u{301} 😀"
        let suffix = command == .codeBlock ? "after\n" : "\rafter\n"
        let source = prefix + body + suffix
        let range = NSRange(location: prefix.utf16.count, length: body.utf16.count)
        let expected: String
        switch command {
        case .link: expected = prefix + "[" + body + "](destination)" + suffix
        case .imageReference: expected = prefix + "![" + body + "](destination)" + suffix
        case .codeBlock: expected = prefix + "````\r\n" + body + "````\r\n" + suffix
        default: throw StructureCheckFailure("Unexpected structural command")
        }
        var reported = source
        var reportedRange = range
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let undoDelegate = StructureUndoDelegate()
        undoDelegate.manager.groupsByEvent = false
        window.delegate = undoDelegate
        let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: range, isEditable: true) {
            reported = $0; reportedRange = $2
        })
        window.contentView = host
        defer {
            structureStage(command.title + " test-owned cleanup")
            // Finish assertions before retiring callbacks/undo in this private
            // host. Production source-view teardown remains unchanged.
            if let text = structureFind(host) {
                text.onTextStateChanged = nil
                text.delegate = nil
            }
            window.makeFirstResponder(nil)
            undoDelegate.manager.removeAllActions()
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
        try await structureWait("structural source attachment") { host.layoutSubtreeIfNeeded(); return structureFind(host) != nil }
        guard let text = structureFind(host) else { throw StructureCheckFailure("Native structural source missing") }
        try structureRequire(window.makeFirstResponder(text), "Structural native source focus unavailable")
        text.setSelectedRange(range)
        let menu = text.makeMarkdownMenu()
        guard let index = menu.items.firstIndex(where: { $0.title == command.title }), menu.items[index].isEnabled else {
            throw StructureCheckFailure("Enabled structural menu command missing: " + command.title)
        }
        structureStage(command.title + " menu action")
        menu.performActionForItem(at: index)
        try structureRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                             "Structural menu command changed literal source or failed to report it")
        let selected = (text.string as NSString).substring(with: text.selectedRange())
        try structureRequire(SourceSelection.sameText(selected, command == .codeBlock ? body : "destination") &&
            reportedRange == text.selectedRange() && window.firstResponder === text &&
            !text.isRichText && !text.isAutomaticLinkDetectionEnabled,
            "Structural insertion lost destination/body selection or changed focus/plain-source policy")
        if command != .codeBlock {
            structureStage(command.title + " destination typing/undo")
            // Replace the selected placeholder as an ordinary separate native
            // typing intent. No URL/file is resolved or opened by this probe.
            undoDelegate.manager.beginUndoGrouping()
            text.insertText("notes.md", replacementRange: NSRange(location: NSNotFound, length: 0))
            undoDelegate.manager.endUndoGrouping()
            let edited = expected.replacingOccurrences(of: "destination", with: "notes.md")
            try structureRequire(SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited),
                                 "Typing into the selected destination replaced another source range")
            try structureRequire(undoDelegate.manager.canUndo, "Destination typing has no native undo")
            undoDelegate.manager.undo()
            try structureRequire(SourceSelection.sameText(text.string, expected), "Destination undo lost template source")
        }
        try structureRequire(undoDelegate.manager.canUndo, "Structural menu insertion has no native undo")
        structureStage(command.title + " insertion undo/redo")
        undoDelegate.manager.undo()
        try structureRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source),
                             "Structural undo did not restore byte-exact original source")
        try structureRequire(undoDelegate.manager.canRedo, "Structural menu insertion has no native redo")
        undoDelegate.manager.redo()
        try structureRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                             "Structural redo did not restore template/fence bytes")
        try structureRequire(!window.isVisible && !NSApplication.shared.isActive, "Structural native probe showed or activated a window")
    }
    print("PASS native link/image/code-block source: actual menu targets, selected editable destination/body, exact BOM/NFD/CRLF/CR, safe fences and separate native insertion/typing undo-redo; no reference resolution")
    print("Passed 1 native structural Markdown AppKit group. Authored actions only; actual OS menus/input, iOS runtime, assets/providers, semantic rendering and release remain open.")
}
