import AppKit
import Darwin
import Foundation
import SwiftUI

private struct LineSelectionFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
@MainActor private func lineRequire(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw LineSelectionFailure(message) }
}
@MainActor private func lineWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw LineSelectionFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
@MainActor private func lineSourceView(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = lineSourceView(child) { return text } }
    return nil
}
@MainActor private final class LineUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}
@MainActor private final class LineFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private struct LineWorkspaceSnapshot: Equatable {
    let files: [String]
    let bytes: [String: Data]
    let modified: [String: Date]
    init(root: URL) throws {
        files = [""] + (try FileManager.default.subpathsOfDirectory(atPath: root.path)).sorted()
        var bytes: [String: Data] = [:], modified: [String: Date] = [:]
        for path in files {
            let url = root.appendingPathComponent(path)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if attrs[.type] as? FileAttributeType == .typeRegular { bytes[path] = try Data(contentsOf: url) }
            modified[path] = attrs[.modificationDate] as? Date
        }
        self.bytes = bytes; self.modified = modified
    }
}


private struct LineRefusalSnapshot: Equatable {
    let source: Data
    let selections: [NSRange]
    let reported: Data
    let reportedSelection: NSRange
    let focus: ObjectIdentifier?
    let marked: NSRange
    let canUndo: Bool
    let canRedo: Bool
    let undoName: String?
    let redoName: String?
    @MainActor init(_ text: MacSourceTextView, reported: String, selection: NSRange, window: NSWindow) {
        source = Data(text.string.utf8); selections = text.selectedRanges.map(\.rangeValue)
        self.reported = Data(reported.utf8); reportedSelection = selection
        focus = window.firstResponder.map { ObjectIdentifier($0) }; marked = text.markedRange()
        canUndo = text.undoManager?.canUndo ?? false; canRedo = text.undoManager?.canRedo ?? false
        undoName = text.undoManager?.undoActionName; redoName = text.undoManager?.redoActionName
    }
}

@MainActor private func lineChoose(_ text: MacSourceTextView) throws {
    let item = text.makeSourceLineSelectionItem(), menu = NSMenu()
    try lineRequire(item.title == SourceLineSelection.title && item.isEnabled, "Source-line action missing or disabled")
    menu.addItem(item); menu.update()
    try lineRequire(item.isEnabled, "Root menu validation disabled a fresh source-line plan")
    menu.performActionForItem(at: 0)
}

@MainActor private func sourceLineNativeNavigation() async throws {
    let source = "\u{FEFF}first Cafe\u{301} 😀\r\nsecond\r\n\nlast"
    let firstLine = NSRange(location: 1, length: "first Cafe\u{301} 😀\r\n".utf16.count)
    let caret = NSRange(location: 3, length: 0)
    var reported = source, reportedSelection = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = LineUndoDelegate(); undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 400)); window.contentView = container
    let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: caret, isEditable: true) {
        reported = $0; reportedSelection = $2
    })
    host.frame = container.bounds; container.addSubview(host)
    let sentinel = LineFocusSentinel(frame: NSRect(x: 0, y: 0, width: 1, height: 1)); container.addSubview(sentinel)
    defer {
        if let text = lineSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.makeFirstResponder(nil); undoDelegate.manager.removeAllActions()
        window.contentView = nil; window.delegate = nil; window.close()
    }
    try await lineWait("source-line editor") { host.layoutSubtreeIfNeeded(); return lineSourceView(host) != nil }
    guard let text = lineSourceView(host) else { throw LineSelectionFailure("Source-line editor missing") }
    try lineRequire(window.makeFirstResponder(text), "Cannot focus source-line editor")
    let undo = undoDelegate.manager
    text.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    undo.beginUndoGrouping(); text.insertText(" typed", replacementRange: NSRange(location: NSNotFound, length: 0)); undo.endUndoGrouping()
    let edited = source + " typed", actionName = undo.undoActionName
    text.setSelectedRange(caret); try lineChoose(text)
    try lineRequire(text.selectedRange() == firstLine && reportedSelection == firstLine &&
        SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited) &&
        window.firstResponder === text && text.undoManager === undo && undo.canUndo && undo.undoActionName == actionName,
        "Line selection changed source/undo/focus or lost exact ending/BOM/model range")
    let noOp = text.makeSourceLineSelectionItem(), noOpMenu = NSMenu()
    noOpMenu.addItem(noOp); noOpMenu.update()
    try lineRequire(!noOp.isEnabled, "Already-expanded source-line action was enabled")
    undo.undo(); try lineRequire(SourceSelection.sameText(text.string, source), "Line selection added a text undo step")
    undo.redo(); try lineRequire(SourceSelection.sameText(text.string, edited), "Line selection lost typing redo")
    func inert(_ label: String, _ action: () throws -> Void) throws {
        let before = LineRefusalSnapshot(text, reported: reported, selection: reportedSelection, window: window)
        try action()
        try lineRequire(before == LineRefusalSnapshot(text, reported: reported, selection: reportedSelection, window: window),
                        label + " changed source/ranges/report/focus/composition/undo")
    }
    text.setSelectedRange(caret)
    let staleItem = text.makeSourceLineSelectionItem(), staleMenu = NSMenu()
    try lineRequire(staleItem.isEnabled, "Stale-caret line control was not enabled")
    staleMenu.autoenablesItems = false; staleMenu.addItem(staleItem)
    text.setSelectedRange(NSRange(location: 4, length: 0))
    try inert("Stale-caret line action") { staleMenu.performActionForItem(at: 0) }
    text.setSelectedRange(caret)
    let oldSourceItem = text.makeSourceLineSelectionItem(), oldSourceMenu = NSMenu()
    try lineRequire(oldSourceItem.isEnabled, "Stale-source line control was not enabled")
    oldSourceMenu.autoenablesItems = false; oldSourceMenu.addItem(oldSourceItem)
    undo.beginUndoGrouping(); text.insertText("tail", replacementRange: NSRange(location: text.string.utf16.count, length: 0)); undo.endUndoGrouping()
    text.setSelectedRange(caret)
    try inert("Stale-source line action") { oldSourceMenu.performActionForItem(at: 0) }
    undo.undo(); text.setSelectedRange(caret)
    guard let plan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw LineSelectionFailure("Current line guard plan missing") }
    text.isEditable = false
    try lineRequire(window.makeFirstResponder(text) && plan.matches(source: text.string, selection: text.selectedRange()), "Read-only line control lost matching plan/focus")
    let readOnlyItem = text.makeSourceLineSelectionItem(), readOnlyMenu = NSMenu()
    readOnlyMenu.addItem(readOnlyItem); readOnlyMenu.update()
    try lineRequire(!readOnlyItem.isEnabled, "Root menu validation enabled read-only line action")
    try inert("Read-only line action") { try lineRequire(!text.applySourceNavigation(plan), "Read-only line action accepted") }
    text.isEditable = true
    try lineRequire(window.makeFirstResponder(sentinel) && plan.matches(source: text.string, selection: text.selectedRange()), "Cannot prepare matching non-source line control")
    try inert("Non-source line action") { try lineRequire(!text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(plan), "Line action took non-source focus") }
    try lineRequire(window.makeFirstResponder(text), "Cannot restore line focus")
    let second = (edited as NSString).range(of: "second")
    text.setSelectedRanges([NSValue(range: NSRange(location: 3, length: 1)), NSValue(range: NSRange(location: second.location + 1, length: 1))], affinity: .downstream, stillSelecting: false)
    guard let multiplePlan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw LineSelectionFailure("Multiple-selection line control missing") }
    try inert("Multiple-selection line action") {
        try lineRequire(text.selectedRanges.count == 2 && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(multiplePlan), "Multiple-selection line action accepted")
    }
    text.setSelectedRange(caret); text.breakUndoCoalescing(); undo.removeAllActions(); undo.groupsByEvent = true
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    guard let markedPlan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw LineSelectionFailure("Marked line control missing") }
    try inert("Composing line action") {
        try lineRequire(text.hasMarkedText() && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(markedPlan), "Line action moved/ended marked text")
    }
    text.unmarkText(); text.string = edited; text.setSelectedRange(caret)
    let detachedItem = text.makeSourceLineSelectionItem(), detachedMenu = NSMenu()
    guard let detachedPlan = SourceLineSelection.make(source: text.string, selection: caret) else { throw LineSelectionFailure("Detached line control missing") }
    try lineRequire(detachedItem.isEnabled, "Detached line control was not initially enabled")
    detachedMenu.autoenablesItems = false; detachedMenu.addItem(detachedItem); host.removeFromSuperview()
    try inert("Detached line action") {
        detachedMenu.performActionForItem(at: 0)
        try lineRequire(text.window == nil && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(detachedPlan), "Detached line action accepted")
    }
    try lineRequire(!window.isVisible && !NSApplication.shared.isActive, "Line selection showed or activated a window")
}

@MainActor private func sourceLineWorkspaceRecovery() async throws {
    guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else { throw LineSelectionFailure("Cannot resolve physical line fixture root") }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("MarkrightSourceLineChecks-" + UUID().uuidString, isDirectory: true)
    free(physical)
    defer {
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Line fixture cleanup warning: \(error)\n".utf8)) }
    }
    let source = "\u{FEFF}first Cafe\u{301} 😀\r\nsecond\r\n\nlast", caret = NSRange(location: 3, length: 0)
    let workspace = MacCollectionWorkspaceModel(store: CollectionStore(root: root))
    _ = await workspace.createCollection("Editing"); _ = await workspace.createDocument(name: "Lines.md", source: source)
    guard let session = workspace.session else { throw LineSelectionFailure("Line session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let host = window.contentView else { throw LineSelectionFailure("Line workspace missing") }
    defer {
        if let text = lineSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.delegate = nil; window.contentViewController = nil; window.close()
    }
    try await lineWait("line workspace") { host.layoutSubtreeIfNeeded(); return !workspace.isBusy && lineSourceView(host)?.isEditable == true }
    guard let text = lineSourceView(host) else { throw LineSelectionFailure("Line workspace source missing") }
    try lineRequire(window.makeFirstResponder(text), "Cannot focus line workspace")
    text.setSelectedRange(caret)
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision, cleanID = session.recoveryDraft?.id
    guard let cleanPlan = SourceLineSelection.make(source: source, selection: caret) else { throw LineSelectionFailure("Clean line plan missing") }
    let cleanBefore = try LineWorkspaceSnapshot(root: root)
    try lineChoose(text); try await Task.sleep(for: .milliseconds(650))
    let cleanAfter = try LineWorkspaceSnapshot(root: root)
    try lineRequire(cleanBefore == cleanAfter && session.model.sourceRevision == revision && session.model.editingGeneration == generation &&
        session.recoveryDraft?.id == cleanID && SourceSelection.sameText(session.model.source, source) &&
        text.selectedRange() == cleanPlan.destination && session.model.documentSelection == cleanPlan.destination &&
        lineSourceView(host) === text && workspace.session === session && window.firstResponder === text,
        "Clean line selection changed filesystem/source/recovery/generation or lost exact selection/editor/focus")
    let file = root.appendingPathComponent("Editing/Lines.md"), external = Data("external original stays untouched\r\n".utf8)
    try external.write(to: file, options: .atomic)
    text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0)); text.insertText("unsaved", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await lineWait("line conflict checkpoint") { session.errorMessage != nil && session.canKeepRecovery && !session.isSaving }
    let currentID = session.recoveryDraft?.id
    try lineRequire(currentID != nil, "Line conflict checkpoint missing")
    try await Task.sleep(for: .milliseconds(650))
    try lineRequire(session.canKeepRecovery && !session.isSaving && session.recoveryDraft?.id == currentID, "Line conflict checkpoint not quiescent")
    text.setSelectedRange(caret)
    let dirtySource = session.model.source, dirtyRevision = session.model.sourceRevision
    guard let dirtyPlan = SourceLineSelection.make(source: dirtySource, selection: caret) else { throw LineSelectionFailure("Dirty line plan missing") }
    let dirtyBefore = try LineWorkspaceSnapshot(root: root)
    try lineChoose(text); try await Task.sleep(for: .milliseconds(650))
    let dirtyAfter = try LineWorkspaceSnapshot(root: root)
    try lineRequire(dirtyBefore == dirtyAfter && session.recoveryDraft?.id == currentID && session.canKeepRecovery &&
        session.dirty && !session.canClose && !session.isSaving && session.model.sourceRevision == dirtyRevision &&
        session.model.editingGeneration == generation && SourceSelection.sameText(session.model.source, dirtySource) &&
        SourceSelection.sameText(text.string, dirtySource) && text.selectedRange() == dirtyPlan.destination &&
        session.model.documentSelection == dirtyPlan.destination && lineSourceView(host) === text && workspace.session === session &&
        window.firstResponder === text, "Conflicted line selection changed settled disk/current recovery/source authority or editor/selection/focus")
    let disk = try Data(contentsOf: file)
    try lineRequire(disk == external, "Line selection overwrote the conflicting original")
}

@MainActor func runSourceLineSelectionChecks() async throws {
    try await sourceLineNativeNavigation()
    try await sourceLineWorkspaceRecovery()
    print("PASS native select source lines: actual menu and root validation, full physical ending/BOM-excluded selection, native/model/focus retained, typing undo/redo unchanged; exact refusal state and clean/conflicted whole-workspace bytes/mtime/current checkpoint unchanged after 650 ms")
    print("Passed 1 native source-line selection AppKit group. Authored actions only; OS menus/input/IME, UIKit runtime, VoiceOver, full authoring/security/device/release acceptance remain open.")
}
