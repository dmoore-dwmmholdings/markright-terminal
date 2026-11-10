import AppKit
import Darwin
import Foundation
import SwiftUI

private struct TaskMarkerFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
@MainActor private func taskRequire(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw TaskMarkerFailure(message) }
}
@MainActor private func taskWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TaskMarkerFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
@MainActor private func taskSource(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = taskSource(child) { return text } }
    return nil
}
@MainActor private final class TaskUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}
@MainActor private final class TaskFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}
@MainActor private func taskChoose(_ text: MacSourceTextView) throws {
    let item = text.makeTaskMarkerItem()
    try taskRequire(item.title == TaskMarkerEdit.title && item.isEnabled, "Task marker action unavailable")
    // Exercise root-context-menu auto-validation too: invalid plans must not
    // become enabled merely because their retained target implements an action.
    let menu = NSMenu(); menu.addItem(item); menu.update()
    try taskRequire(item.isEnabled, "Native task menu validation disabled a fresh plan")
    menu.performActionForItem(at: 0)
}

@MainActor private func taskMarkerNativeEditing() async throws {
    let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n  + [X]\tsecond\r\n \t\n* [x] third\r"
    let checked = "\u{FEFF}- [x] Cafe\u{301} 😀\r\n  + [X]\tsecond\r\n \t\n* [x] third\r"
    var reported = source, reportedSelection = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = TaskUndoDelegate(); undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 400)); window.contentView = container
    let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: SourceSelection.beginning, isEditable: true) {
        reported = $0; reportedSelection = $2
    })
    host.frame = container.bounds; container.addSubview(host)
    let sentinel = TaskFocusSentinel(frame: .zero); container.addSubview(sentinel)
    defer {
        if let text = taskSource(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.makeFirstResponder(nil); undoDelegate.manager.removeAllActions()
        window.contentView = nil; window.delegate = nil; window.close()
    }
    try await taskWait("task editor") { host.layoutSubtreeIfNeeded(); return taskSource(host) != nil }
    guard let text = taskSource(host) else { throw TaskMarkerFailure("Task source absent") }
    try taskRequire(window.makeFirstResponder(text), "Cannot focus task source")
    let undo = undoDelegate.manager, caret = NSRange(location: 10, length: 0)
    text.setSelectedRange(caret)
    try taskChoose(text)
    try taskRequire(SourceSelection.sameText(text.string, checked) && SourceSelection.sameText(reported, checked) &&
        text.selectedRange() == caret && reportedSelection == caret && window.firstResponder === text &&
        undo.undoActionName == TaskMarkerEdit.title, "Caret task edit lost exact source, caret, focus or named undo")
    undo.undo()
    try taskRequire(SourceSelection.sameText(text.string, source) && SourceSelection.sameText(reported, source), "Task undo lost original bytes")
    undo.redo()
    try taskRequire(SourceSelection.sameText(text.string, checked), "Task redo lost state")
    undo.undo()
    let batch = NSRange(location: 0, length: source.utf16.count)
    text.setSelectedRange(batch); try taskChoose(text)
    try taskRequire(SourceSelection.sameText(text.string, checked) && text.selectedRange() == batch, "Mixed task batch did not check only unchecked states")
    try taskChoose(text)
    let cleared = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n  + [ ]\tsecond\r\n \t\n* [ ] third\r"
    try taskRequire(SourceSelection.sameText(text.string, cleared) && SourceSelection.sameText(reported, cleared), "Checked task batch did not clear x/X")
    undo.undo(); undo.undo()
    try taskRequire(SourceSelection.sameText(text.string, source), "Batch task edits did not have separate undo steps")
    text.setSelectedRange(caret); try taskChoose(text)
    undo.beginUndoGrouping(); text.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0)); undo.endUndoGrouping()
    undo.undo()
    try taskRequire(SourceSelection.sameText(text.string, checked), "Typing undo consumed task edit")
    undo.undo()
    try taskRequire(SourceSelection.sameText(text.string, source), "Task undo did not remain separate from typing")
    undo.redo(); undo.redo(); undo.undo(); undo.undo()
    text.setSelectedRange(caret)
    let staleCaret = NSMenu(); staleCaret.autoenablesItems = false; staleCaret.addItem(text.makeTaskMarkerItem())
    text.setSelectedRange(NSRange(location: caret.location + 1, length: 0)); staleCaret.performActionForItem(at: 0)
    try taskRequire(SourceSelection.sameText(text.string, source), "Retained task action ignored stale caret")
    text.setSelectedRange(caret)
    let staleSource = NSMenu(); staleSource.autoenablesItems = false; staleSource.addItem(text.makeTaskMarkerItem())
    undo.beginUndoGrouping(); text.insertText("tail", replacementRange: NSRange(location: source.utf16.count, length: 0)); undo.endUndoGrouping()
    text.setSelectedRange(caret); staleSource.performActionForItem(at: 0)
    try taskRequire(SourceSelection.sameText(text.string, source + "tail"), "Retained task action ignored stale source")
    undo.undo(); text.setSelectedRange(caret)
    guard let plan = TaskMarkerEdit.make(source: source, selection: caret) else { throw TaskMarkerFailure("Task guard plan absent") }
    text.isEditable = false
    let inactiveItem = text.makeTaskMarkerItem(), inactiveMenu = NSMenu()
    inactiveMenu.addItem(inactiveItem); inactiveMenu.update()
    try taskRequire(!inactiveItem.isEnabled, "Automatic root menu validation enabled a refused task edit")
    try taskRequire(!text.makeTaskMarkerItem().isEnabled && !text.applyMarkdownInsertion(plan), "Read-only task action accepted")
    text.isEditable = true
    try taskRequire(window.makeFirstResponder(sentinel), "Cannot prepare non-source task focus")
    try taskRequire(!text.makeTaskMarkerItem().isEnabled && !text.applyMarkdownInsertion(plan) && window.firstResponder === sentinel,
                    "Task action took non-source focus")
    try taskRequire(window.makeFirstResponder(text), "Cannot restore task focus")
    text.setSelectedRanges([NSValue(range: caret), NSValue(range: NSRange(location: 1, length: 2))], affinity: .downstream, stillSelecting: false)
    try taskRequire(text.selectedRanges.count == 2 && !text.makeTaskMarkerItem().isEnabled && !text.applyMarkdownInsertion(plan), "Multiple-selection task action accepted")
    text.setSelectedRange(caret); text.breakUndoCoalescing(); undo.removeAllActions(); undo.groupsByEvent = true
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    try taskRequire(text.hasMarkedText() && !text.makeTaskMarkerItem().isEnabled && !text.applyMarkdownInsertion(plan), "Task action ended or edited composition")
    text.unmarkText()
    // Restore only owned synthetic text before testing detached controls.
    text.string = source; text.setSelectedRange(caret)
    try taskRequire(text.makeTaskMarkerItem().isEnabled, "Task detached positive control failed")
    host.removeFromSuperview()
    try taskRequire(text.window == nil && !text.makeTaskMarkerItem().isEnabled && !text.applyMarkdownInsertion(plan), "Detached task action accepted")
    try taskRequire(!window.isVisible && !NSApplication.shared.isActive, "Task probe activated/showed a window")
}

@MainActor private func taskMarkerWorkspaceRecovery() async throws {
    guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
        throw TaskMarkerFailure("Cannot resolve synthetic root")
    }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("MarkrightTaskMarkerChecks-" + UUID().uuidString, isDirectory: true)
    free(physical)
    defer {
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Task fixture cleanup warning: \(error)\n".utf8)) }
    }
    let source = "\u{FEFF}- [ ] Cafe\u{301} 😀\r\n+ [X] second\r"
    let checked = "\u{FEFF}- [x] Cafe\u{301} 😀\r\n+ [X] second\r"
    let workspace = MacCollectionWorkspaceModel(store: CollectionStore(root: root))
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Task.md", source: source)
    guard let session = workspace.session else { throw TaskMarkerFailure("Task session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let host = window.contentView else { throw TaskMarkerFailure("Task workspace absent") }
    defer {
        if let text = taskSource(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.delegate = nil; window.contentViewController = nil; window.close()
    }
    try await taskWait("task workspace") { host.layoutSubtreeIfNeeded(); return !workspace.isBusy && taskSource(host)?.isEditable == true }
    guard let text = taskSource(host) else { throw TaskMarkerFailure("Workspace task source absent") }
    try taskRequire(window.makeFirstResponder(text), "Cannot focus workspace task source")
    let baseline = session.document.baseline
    let generation = session.model.editingGeneration, caret = NSRange(location: 9, length: 0)
    let file = root.appendingPathComponent("Editing/Task.md")
    text.setSelectedRange(caret); try taskChoose(text)
    try await taskWait("task normal autosave") { !session.dirty && !session.isSaving && session.errorMessage == nil && SourceSelection.sameText(session.model.source, checked) }
    let saved = try Data(contentsOf: file)
    try taskRequire(saved == Data(checked.utf8) && text.selectedRange() == caret && session.model.documentSelection == caret &&
        taskSource(host) === text && workspace.session === session && session.model.editingGeneration == generation && window.firstResponder === text,
        "Task edit did not use ordinary exact-source autosave or retain session/editor/caret/focus")
    let external = Data("outside source preserved\r\n".utf8)
    try external.write(to: file, options: .atomic)
    text.setSelectedRange(caret); try taskChoose(text)
    try await taskWait("task conflict recovery") { session.errorMessage != nil && session.canKeepRecovery && !session.isSaving && SourceSelection.sameText(session.model.source, source) }
    let checkpoint = session.recoveryDraft?.id
    try taskRequire(checkpoint != nil, "Task conflict lacks recovery checkpoint")
    try await Task.sleep(for: .milliseconds(650))
    let disk = try Data(contentsOf: file)
    let recovery = try await workspace.store.recoveries()
    try taskRequire(disk == external && recovery.drafts.contains { $0.id == checkpoint && SourceSelection.sameText($0.source, source) } &&
        session.document.baseline == Data(checked.utf8) && baseline == Data(source.utf8) &&
        session.recoveryDraft?.id == checkpoint && session.canKeepRecovery && session.dirty && !session.canClose && !session.isSaving &&
        taskSource(host) === text && workspace.session === session && session.model.editingGeneration == generation &&
        session.model.documentSelection == caret && text.selectedRange() == caret && window.firstResponder === text,
        "Task edit overwrote external original or lost settled current full-source recovery/caret/editor")
}

@MainActor func runTaskMarkerChecks() async throws {
    try await taskMarkerNativeEditing()
    try await taskMarkerWorkspaceRecovery()
    print("PASS native task markers: actual caret/batch menu targets, exact BOM/NFD/emoji/mixed endings, x/X states, retained caret/model/focus, named separate insertion/typing undo-redo, stale/read-only/non-source/multiple/marked/detached guards; normal autosave and settled conflicted full-source recovery without overwriting original")
    print("Passed 1 native task-marker AppKit group. Authored actions only; OS input/IME, UIKit runtime, VoiceOver, parser/context/security and release acceptance remain open.")
}
