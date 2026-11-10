import AppKit
import Foundation
import SwiftUI

private struct TableCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func tableRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TableCheckFailure(message) }
}

@MainActor private func tableFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = tableFind(child) { return text } }
    return nil
}

@MainActor private final class TableUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor func runMarkdownTableChecks() async throws {
    let prefix = "\u{FEFF}before\r\n"
    let grid = "Name\tValue\tUnit\r\nCafe\u{301} 😀\t42\tbits\rlast\t0\tbyte\n"
    let expectedGrid = "| Name | Value | Unit |\r\n| --- | --- | --- |\r\n| Cafe\u{301} 😀 | 42 | bits |\r| last | 0 | byte |\n"
    let starter = "| Column 1 | Column 2 |\r\n| --- | --- |\r\n| Value 1 | Value 2 |"
    let cases: [(source: String, range: NSRange, expected: String, selected: String)] = [
        (prefix + grid + "after", NSRange(location: prefix.utf16.count, length: grid.utf16.count), prefix + expectedGrid + "after", "Cafe\u{301} 😀"),
        (prefix + "\r\nafter", NSRange(location: prefix.utf16.count, length: 0), prefix + starter + "\r\nafter", "Value 1"),
        ("A\tB\n\tvalue\n", NSRange(location: 0, length: "A\tB\n\tvalue\n".utf16.count), "| A | B |\n| --- | --- |\n|  | value |\n", ""),
    ]
    for item in cases {
        var reported = item.source
        var reportedRange = item.range
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 390),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let undoDelegate = TableUndoDelegate()
        undoDelegate.manager.groupsByEvent = false
        window.delegate = undoDelegate
        let host = NSHostingView(rootView: MacSourceEditor(value: item.source, selection: item.range, isEditable: true) {
            reported = $0; reportedRange = $2
        })
        window.contentView = host
        defer {
            if let text = tableFind(host) { text.onTextStateChanged = nil; text.delegate = nil }
            window.makeFirstResponder(nil)
            undoDelegate.manager.removeAllActions()
            window.contentView = nil
            window.delegate = nil
            window.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        while tableFind(host) == nil {
            guard ContinuousClock.now < deadline else { throw TableCheckFailure("Native table source attachment timed out") }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let text = tableFind(host) else { throw TableCheckFailure("Native table source missing") }
        try tableRequire(window.makeFirstResponder(text), "Native table source focus unavailable")
        text.setSelectedRange(item.range)
        let menu = text.makeMarkdownMenu()
        guard let index = menu.items.firstIndex(where: { $0.title == "Table" }), menu.items[index].isEnabled else {
            throw TableCheckFailure("Enabled native Table command missing")
        }
        menu.performActionForItem(at: index)
        try tableRequire(SourceSelection.sameText(text.string, item.expected) && SourceSelection.sameText(reported, item.expected),
                         "Native table conversion/starter changed cell/BOM/endings/outside source or failed to report")
        let firstCellRange = text.selectedRange()
        try tableRequire(SourceSelection.sameText((text.string as NSString).substring(with: firstCellRange), item.selected) &&
            firstCellRange == reportedRange && window.firstResponder === text,
            "Native table command did not select the first data cell or retain focus")
        let edited = (item.expected as NSString).replacingCharacters(in: firstCellRange, with: "edited cell")
        undoDelegate.manager.beginUndoGrouping()
        text.insertText("edited cell", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoDelegate.manager.endUndoGrouping()
        try tableRequire(SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited),
                         "Native typing replaced table syntax or the wrong cell")
        try tableRequire(undoDelegate.manager.canUndo, "Native table cell typing lacks undo")
        undoDelegate.manager.undo()
        try tableRequire(SourceSelection.sameText(text.string, item.expected), "Cell typing undo failed to restore table")
        undoDelegate.manager.undo()
        try tableRequire(SourceSelection.sameText(text.string, item.source) && SourceSelection.sameText(reported, item.source),
                         "Table insertion undo failed to restore exact TSV/source bytes")
        try tableRequire(undoDelegate.manager.canRedo, "Native table insertion lacks redo")
        undoDelegate.manager.redo()
        try tableRequire(SourceSelection.sameText(text.string, item.expected), "Table insertion redo changed exact bytes")
        try tableRequire(!window.isVisible && !NSApplication.shared.isActive, "Table probe showed or activated a window")
    }
    print("PASS native table source: real menu starter/TSV conversion, exact cells/BOM/mixed endings and outside bytes, first data cell including empty-cell caret, typing and separate native undo/redo")
    print("Passed 1 native table AppKit group. Authored actions only; OS menus/input, iOS runtime, semantic table rendering/grid UI and release remain open.")
}
