import AppKit
import Darwin
import Foundation
import SwiftUI

private struct SelectionFindFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
@MainActor private func findRequire(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw SelectionFindFailure(message) }
}
@MainActor private func findWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw SelectionFindFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
@MainActor private func findSourceView(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = findSourceView(child) { return text } }
    return nil
}
@MainActor private final class FindUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}
@MainActor private final class FindFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private func selectionFindNativeNavigation() async throws {
    let literal = "\u{FEFF}cat Cafe\u{301} 😀\r\ncat\rCAT\ncat"
    let first = NSRange(location: 1, length: 3)
    var reported = literal, reportedRange = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = FindUndoDelegate()
    undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 400))
    window.contentView = container
    let host = NSHostingView(rootView: MacSourceEditor(value: literal, selection: first, isEditable: true) {
        reported = $0; reportedRange = $2
    })
    host.frame = container.bounds; container.addSubview(host)
    let sentinel = FindFocusSentinel(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    container.addSubview(sentinel)
    defer {
        if let text = findSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.makeFirstResponder(nil); undoDelegate.manager.removeAllActions()
        window.contentView = nil; window.delegate = nil; window.close()
    }
    try await findWait("find source attachment") { host.layoutSubtreeIfNeeded(); return findSourceView(host) != nil }
    guard let text = findSourceView(host) else { throw SelectionFindFailure("Native find source missing") }
    try findRequire(window.makeFirstResponder(text), "Cannot focus find source")
    text.setSelectedRange(.init(location: literal.utf16.count, length: 0))
    let undo = undoDelegate.manager
    undo.beginUndoGrouping(); text.insertText(" typed", replacementRange: .init(location: NSNotFound, length: 0)); undo.endUndoGrouping()
    let edited = literal + " typed"
    text.setSelectedRange(first)
    let menu = text.makeSelectionFindMenu()
    let report = SourceSelectionFind.make(source: edited, selection: first)
    guard let next = report.next, let previous = report.previous else { throw SelectionFindFailure("Find plans missing") }
    try findRequire(menu.items.map(\.title) == [SourceSelectionFind.nextTitle, SourceSelectionFind.previousTitle] && menu.items.allSatisfy(\.isEnabled),
                    "Native find menu lost fixed titles or enabled actions")
    let actionName = undo.undoActionName
    menu.performActionForItem(at: 0)
    try findRequire(text.selectedRange() == next.destination && reportedRange == next.destination &&
        SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited) &&
        window.firstResponder === text && text.undoManager === undo && undo.canUndo && undo.undoActionName == actionName,
        "Find next changed source/undo/focus or failed to report exact selection")
    text.setSelectedRange(first)
    menu.performActionForItem(at: 1)
    try findRequire(text.selectedRange() == previous.destination && reportedRange == previous.destination,
                    "Actual previous find menu did not wrap to exact last occurrence")
    let wrapped = text.makeSelectionFindMenu()
    wrapped.performActionForItem(at: 0)
    try findRequire(text.selectedRange() == first && reportedRange == first, "Actual next find menu did not wrap")
    undo.undo()
    try findRequire(SourceSelection.sameText(text.string, literal), "Find added a text undo step or lost typing undo")
    undo.redo()
    try findRequire(SourceSelection.sameText(text.string, edited), "Find lost typing redo")

    text.setSelectedRange(first)
    let staleMenu = text.makeSelectionFindMenu()
    text.setSelectedRange(.init(location: 5, length: 0))
    staleMenu.performActionForItem(at: 0)
    try findRequire(text.selectedRange() == NSRange(location: 5, length: 0), "Retained find ignored stale selection")
    text.setSelectedRange(first)
    let staleSourceMenu = text.makeSelectionFindMenu()
    undo.beginUndoGrouping(); text.insertText("x", replacementRange: .init(location: text.string.utf16.count, length: 0)); undo.endUndoGrouping()
    text.setSelectedRange(first)
    staleSourceMenu.performActionForItem(at: 0)
    try findRequire(text.selectedRange() == first, "Retained find ignored stale source")
    undo.undo(); text.setSelectedRange(first)
    func currentPlan() throws -> SourceNavigationPlan {
        guard let plan = SourceNavigationPlan.make(source: text.string, selection: text.selectedRange(), destination: first) else {
            throw SelectionFindFailure("Current guard-control plan missing")
        }
        return plan
    }
    func requireDisabledMenu(_ label: String) throws {
        let items = text.makeSelectionFindMenu().items
        try findRequire(items.count == 3 && items.allSatisfy { !$0.isEnabled }, label)
    }
    let readOnlyMenu = text.makeSelectionFindMenu()
    text.isEditable = false
    readOnlyMenu.performActionForItem(at: 0)
    let readOnlyPlan = try currentPlan()
    try findRequire(text.selectedRange() == first && !text.applySourceNavigation(readOnlyPlan), "Read-only source/recovery find accepted")
    try requireDisabledMenu("Read-only find menu enabled")
    text.isEditable = true
    let inactiveMenu = text.makeSelectionFindMenu()
    try findRequire(window.makeFirstResponder(sentinel), "Cannot prepare non-source focus")
    inactiveMenu.performActionForItem(at: 0)
    let inactivePlan = try currentPlan()
    try findRequire(!text.applySourceNavigation(inactivePlan) && window.firstResponder === sentinel && text.selectedRange() == first,
                    "Find stole non-source focus")
    try requireDisabledMenu("Inactive find menu enabled")
    try findRequire(window.makeFirstResponder(text), "Cannot restore find source focus")
    text.setSelectedRanges([NSValue(range: first), NSValue(range: NSRange(location: 5, length: 2))], affinity: .downstream, stillSelecting: false)
    try findRequire(text.selectedRanges.count == 2, "Find multiple-selection positive control failed")
    let multiplePlan = try currentPlan()
    try findRequire(!text.applySourceNavigation(multiplePlan), "Multiple-selection find accepted")
    try requireDisabledMenu("Multiple-selection find menu enabled")
    text.setSelectedRange(.init(location: text.string.utf16.count, length: 0))
    text.breakUndoCoalescing(); undo.removeAllActions(); undo.groupsByEvent = true
    text.setMarkedText("仮", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    try findRequire(text.hasMarkedText(), "Find marked-text positive control failed")
    let markedPlan = try currentPlan()
    try findRequire(!text.applySourceNavigation(markedPlan) && text.hasMarkedText(), "Find moved/ended marked text")
    try requireDisabledMenu("Marked find menu enabled")
    text.unmarkText(); text.setSelectedRange(first)
    let detachedMenu = text.makeSelectionFindMenu(), detachedPlan = try currentPlan()
    host.removeFromSuperview()
    detachedMenu.performActionForItem(at: 0)
    try findRequire(text.window == nil && text.selectedRange() == first && !text.applySourceNavigation(detachedPlan), "Detached find accepted")
    try requireDisabledMenu("Detached find menu enabled")
}

private struct FindWorkspaceSnapshot: Equatable {
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

@MainActor private func selectionFindWorkspaceRecovery() async throws {
    guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
        throw SelectionFindFailure("Cannot resolve owned physical temporary root")
    }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("MarkrightSelectionFindChecks-" + UUID().uuidString, isDirectory: true)
    free(physical)
    defer {
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Find fixture cleanup warning: \(error)\n".utf8)) }
    }
    let store = CollectionStore(root: root), first = NSRange(location: 1, length: 6)
    let workspace = MacCollectionWorkspaceModel(store: store)
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Find.md", source: "\u{FEFF}needle Cafe\u{301} 😀\r\nneedle\rneedle\n")
    guard let session = workspace.session else { throw SelectionFindFailure("Find workspace session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let host = window.contentView else { throw SelectionFindFailure("Find workspace missing") }
    defer {
        if let text = findSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.delegate = nil; window.contentViewController = nil; window.close()
    }
    try await findWait("editable find workspace") { host.layoutSubtreeIfNeeded(); return !workspace.isBusy && findSourceView(host)?.isEditable == true }
    guard let text = findSourceView(host) else { throw SelectionFindFailure("Find workspace source missing") }
    try findRequire(window.makeFirstResponder(text), "Cannot focus workspace find source")
    text.setSelectedRange(first)
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision
    let cleanSource = session.model.source, cleanCheckpoint = session.recoveryDraft?.id
    let cleanBefore = try FindWorkspaceSnapshot(root: root)
    let cleanReport = SourceSelectionFind.make(source: text.string, selection: first)
    let cleanMenu = text.makeSelectionFindMenu()
    try findRequire(cleanReport.next != nil && cleanMenu.items.count == 2 && cleanMenu.items.allSatisfy(\.isEnabled), "Clean find menu not ready")
    cleanMenu.performActionForItem(at: 0)
    try await Task.sleep(for: .milliseconds(650))
    let cleanAfter = try FindWorkspaceSnapshot(root: root)
    try findRequire(cleanBefore == cleanAfter && session.model.sourceRevision == revision && session.model.editingGeneration == generation &&
        text.selectedRange() == cleanReport.next?.destination && session.model.documentSelection == text.selectedRange() &&
        SourceSelection.sameText(text.string, cleanSource) && SourceSelection.sameText(session.model.source, cleanSource) &&
        session.recoveryDraft?.id == cleanCheckpoint && findSourceView(host) === text && workspace.session === session &&
        window.firstResponder === text, "Clean find changed filesystem/generation/checkpoint or lost exact model selection")
    let file = root.appendingPathComponent("Editing/Find.md"), external = Data("outside source stays untouched\r\n".utf8)
    try external.write(to: file, options: .atomic)
    text.setSelectedRange(.init(location: text.string.utf16.count, length: 0))
    text.insertText("unsaved", replacementRange: .init(location: NSNotFound, length: 0))
    try await findWait("find conflict checkpoint") { session.errorMessage != nil && session.canKeepRecovery && !session.isSaving }
    // Prove a settled baseline before measuring selection-only work.
    let settledCheckpoint = session.recoveryDraft?.id
    try findRequire(settledCheckpoint != nil, "Conflict recovery checkpoint missing")
    try await Task.sleep(for: .milliseconds(650))
    try findRequire(session.canKeepRecovery && !session.isSaving && session.recoveryDraft?.id == settledCheckpoint, "Conflict checkpoint was not quiescent")
    text.setSelectedRange(first)
    let dirtyRevision = session.model.sourceRevision, dirtySource = session.model.source
    let dirtyBefore = try FindWorkspaceSnapshot(root: root)
    let dirtyReport = SourceSelectionFind.make(source: dirtySource, selection: first)
    let dirtyMenu = text.makeSelectionFindMenu()
    try findRequire(dirtyReport.previous != nil && dirtyMenu.items.count == 2 && dirtyMenu.items.allSatisfy(\.isEnabled), "Conflicted find menu not ready")
    dirtyMenu.performActionForItem(at: 1)
    try await Task.sleep(for: .milliseconds(650))
    let dirtyAfter = try FindWorkspaceSnapshot(root: root)
    try findRequire(findSourceView(host) === text && window.firstResponder === text && workspace.session === session &&
        text.selectedRange() == dirtyReport.previous?.destination && session.model.documentSelection == text.selectedRange() &&
        session.model.sourceRevision == dirtyRevision && session.model.editingGeneration == generation &&
        SourceSelection.sameText(session.model.source, dirtySource) && session.recoveryDraft?.id == settledCheckpoint &&
        session.dirty && !session.canClose && session.canKeepRecovery && !session.isSaving && dirtyBefore == dirtyAfter,
        "Conflicted find changed source/selection authority, filesystem or current recovery checkpoint")
    let originalDisk = try Data(contentsOf: file)
    try findRequire(originalDisk == external, "Find overwrote conflicting original")
}

@MainActor func runSourceSelectionFindChecks() async throws {
    try await selectionFindNativeNavigation()
    try await selectionFindWorkspaceRecovery()
    print("PASS native find selected text: actual next/previous menu targets and wrap, exact selection/model/focus, typing undo/redo retained, stale/read-only/non-source/multiple/marked/detached guards; clean/conflicted whole-workspace bytes/mtime/current checkpoint unchanged after 650 ms")
    print("Passed 1 bounded native selected-source find AppKit group. Authored actions only; actual OS input/IME/VoiceOver, UIKit runtime, full authoring, security and release remain open.")
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
    try findRequire(item.title == SourceLineSelection.title && item.isEnabled, "Source-line action missing or disabled")
    menu.addItem(item); menu.update()
    try findRequire(item.isEnabled, "Root menu validation disabled a fresh source-line plan")
    menu.performActionForItem(at: 0)
}

@MainActor private func sourceLineNativeNavigation() async throws {
    let source = "\u{FEFF}first Cafe\u{301} 😀\r\nsecond\r\n\nlast"
    let firstLine = NSRange(location: 1, length: "first Cafe\u{301} 😀\r\n".utf16.count)
    let caret = NSRange(location: 3, length: 0)
    var reported = source, reportedSelection = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = FindUndoDelegate(); undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 400)); window.contentView = container
    let host = NSHostingView(rootView: MacSourceEditor(value: source, selection: caret, isEditable: true) {
        reported = $0; reportedSelection = $2
    })
    host.frame = container.bounds; container.addSubview(host)
    let sentinel = FindFocusSentinel(frame: NSRect(x: 0, y: 0, width: 1, height: 1)); container.addSubview(sentinel)
    defer {
        if let text = findSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.makeFirstResponder(nil); undoDelegate.manager.removeAllActions()
        window.contentView = nil; window.delegate = nil; window.close()
    }
    try await findWait("source-line editor") { host.layoutSubtreeIfNeeded(); return findSourceView(host) != nil }
    guard let text = findSourceView(host) else { throw SelectionFindFailure("Source-line editor missing") }
    try findRequire(window.makeFirstResponder(text), "Cannot focus source-line editor")
    let undo = undoDelegate.manager
    text.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    undo.beginUndoGrouping(); text.insertText(" typed", replacementRange: NSRange(location: NSNotFound, length: 0)); undo.endUndoGrouping()
    let edited = source + " typed", actionName = undo.undoActionName
    text.setSelectedRange(caret); try lineChoose(text)
    try findRequire(text.selectedRange() == firstLine && reportedSelection == firstLine &&
        SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited) &&
        window.firstResponder === text && text.undoManager === undo && undo.canUndo && undo.undoActionName == actionName,
        "Line selection changed source/undo/focus or lost exact ending/BOM/model range")
    let noOp = text.makeSourceLineSelectionItem(), noOpMenu = NSMenu()
    noOpMenu.addItem(noOp); noOpMenu.update()
    try findRequire(!noOp.isEnabled, "Already-expanded source-line action was enabled")
    undo.undo(); try findRequire(SourceSelection.sameText(text.string, source), "Line selection added a text undo step")
    undo.redo(); try findRequire(SourceSelection.sameText(text.string, edited), "Line selection lost typing redo")
    func inert(_ label: String, _ action: () throws -> Void) throws {
        let before = LineRefusalSnapshot(text, reported: reported, selection: reportedSelection, window: window)
        try action()
        try findRequire(before == LineRefusalSnapshot(text, reported: reported, selection: reportedSelection, window: window),
                        label + " changed source/ranges/report/focus/composition/undo")
    }
    text.setSelectedRange(caret)
    let staleItem = text.makeSourceLineSelectionItem(), staleMenu = NSMenu()
    try findRequire(staleItem.isEnabled, "Stale-caret line control was not enabled")
    staleMenu.autoenablesItems = false; staleMenu.addItem(staleItem)
    text.setSelectedRange(NSRange(location: 4, length: 0))
    try inert("Stale-caret line action") { staleMenu.performActionForItem(at: 0) }
    text.setSelectedRange(caret)
    let oldSourceItem = text.makeSourceLineSelectionItem(), oldSourceMenu = NSMenu()
    try findRequire(oldSourceItem.isEnabled, "Stale-source line control was not enabled")
    oldSourceMenu.autoenablesItems = false; oldSourceMenu.addItem(oldSourceItem)
    undo.beginUndoGrouping(); text.insertText("tail", replacementRange: NSRange(location: text.string.utf16.count, length: 0)); undo.endUndoGrouping()
    text.setSelectedRange(caret)
    try inert("Stale-source line action") { oldSourceMenu.performActionForItem(at: 0) }
    undo.undo(); text.setSelectedRange(caret)
    guard let plan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw SelectionFindFailure("Current line guard plan missing") }
    text.isEditable = false
    try findRequire(window.makeFirstResponder(text) && plan.matches(source: text.string, selection: text.selectedRange()), "Read-only line control lost matching plan/focus")
    let readOnlyItem = text.makeSourceLineSelectionItem(), readOnlyMenu = NSMenu()
    readOnlyMenu.addItem(readOnlyItem); readOnlyMenu.update()
    try findRequire(!readOnlyItem.isEnabled, "Root menu validation enabled read-only line action")
    try inert("Read-only line action") { try findRequire(!text.applySourceNavigation(plan), "Read-only line action accepted") }
    text.isEditable = true
    try findRequire(window.makeFirstResponder(sentinel) && plan.matches(source: text.string, selection: text.selectedRange()), "Cannot prepare matching non-source line control")
    try inert("Non-source line action") { try findRequire(!text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(plan), "Line action took non-source focus") }
    try findRequire(window.makeFirstResponder(text), "Cannot restore line focus")
    let second = (edited as NSString).range(of: "second")
    text.setSelectedRanges([NSValue(range: NSRange(location: 3, length: 1)), NSValue(range: NSRange(location: second.location + 1, length: 1))], affinity: .downstream, stillSelecting: false)
    guard let multiplePlan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw SelectionFindFailure("Multiple-selection line control missing") }
    try inert("Multiple-selection line action") {
        try findRequire(text.selectedRanges.count == 2 && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(multiplePlan), "Multiple-selection line action accepted")
    }
    text.setSelectedRange(caret); text.breakUndoCoalescing(); undo.removeAllActions(); undo.groupsByEvent = true
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    guard let markedPlan = SourceLineSelection.make(source: text.string, selection: text.selectedRange()) else { throw SelectionFindFailure("Marked line control missing") }
    try inert("Composing line action") {
        try findRequire(text.hasMarkedText() && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(markedPlan), "Line action moved/ended marked text")
    }
    text.unmarkText(); text.string = edited; text.setSelectedRange(caret)
    let detachedItem = text.makeSourceLineSelectionItem(), detachedMenu = NSMenu()
    guard let detachedPlan = SourceLineSelection.make(source: text.string, selection: caret) else { throw SelectionFindFailure("Detached line control missing") }
    try findRequire(detachedItem.isEnabled, "Detached line control was not initially enabled")
    detachedMenu.autoenablesItems = false; detachedMenu.addItem(detachedItem); host.removeFromSuperview()
    try inert("Detached line action") {
        detachedMenu.performActionForItem(at: 0)
        try findRequire(text.window == nil && !text.makeSourceLineSelectionItem().isEnabled && !text.applySourceNavigation(detachedPlan), "Detached line action accepted")
    }
    try findRequire(!window.isVisible && !NSApplication.shared.isActive, "Line selection showed or activated a window")
}

@MainActor private func sourceLineWorkspaceRecovery() async throws {
    guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else { throw SelectionFindFailure("Cannot resolve physical line fixture root") }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("MarkrightSourceLineChecks-" + UUID().uuidString, isDirectory: true)
    free(physical)
    defer {
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Line fixture cleanup warning: \(error)\n".utf8)) }
    }
    let source = "\u{FEFF}first Cafe\u{301} 😀\r\nsecond\r\n\nlast", caret = NSRange(location: 3, length: 0)
    let workspace = MacCollectionWorkspaceModel(store: CollectionStore(root: root))
    _ = await workspace.createCollection("Editing"); _ = await workspace.createDocument(name: "Lines.md", source: source)
    guard let session = workspace.session else { throw SelectionFindFailure("Line session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let host = window.contentView else { throw SelectionFindFailure("Line workspace missing") }
    defer {
        if let text = findSourceView(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.delegate = nil; window.contentViewController = nil; window.close()
    }
    try await findWait("line workspace") { host.layoutSubtreeIfNeeded(); return !workspace.isBusy && findSourceView(host)?.isEditable == true }
    guard let text = findSourceView(host) else { throw SelectionFindFailure("Line workspace source missing") }
    try findRequire(window.makeFirstResponder(text), "Cannot focus line workspace")
    text.setSelectedRange(caret)
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision, cleanID = session.recoveryDraft?.id
    guard let cleanPlan = SourceLineSelection.make(source: source, selection: caret) else { throw SelectionFindFailure("Clean line plan missing") }
    let cleanBefore = try FindWorkspaceSnapshot(root: root)
    try lineChoose(text); try await Task.sleep(for: .milliseconds(650))
    let cleanAfter = try FindWorkspaceSnapshot(root: root)
    try findRequire(cleanBefore == cleanAfter && session.model.sourceRevision == revision && session.model.editingGeneration == generation &&
        session.recoveryDraft?.id == cleanID && SourceSelection.sameText(session.model.source, source) &&
        text.selectedRange() == cleanPlan.destination && session.model.documentSelection == cleanPlan.destination &&
        findSourceView(host) === text && workspace.session === session && window.firstResponder === text,
        "Clean line selection changed filesystem/source/recovery/generation or lost exact selection/editor/focus")
    let file = root.appendingPathComponent("Editing/Lines.md"), external = Data("external original stays untouched\r\n".utf8)
    try external.write(to: file, options: .atomic)
    text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0)); text.insertText("unsaved", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await findWait("line conflict checkpoint") { session.errorMessage != nil && session.canKeepRecovery && !session.isSaving }
    let currentID = session.recoveryDraft?.id
    try findRequire(currentID != nil, "Line conflict checkpoint missing")
    try await Task.sleep(for: .milliseconds(650))
    try findRequire(session.canKeepRecovery && !session.isSaving && session.recoveryDraft?.id == currentID, "Line conflict checkpoint not quiescent")
    text.setSelectedRange(caret)
    let dirtySource = session.model.source, dirtyRevision = session.model.sourceRevision
    guard let dirtyPlan = SourceLineSelection.make(source: dirtySource, selection: caret) else { throw SelectionFindFailure("Dirty line plan missing") }
    let dirtyBefore = try FindWorkspaceSnapshot(root: root)
    try lineChoose(text); try await Task.sleep(for: .milliseconds(650))
    let dirtyAfter = try FindWorkspaceSnapshot(root: root)
    try findRequire(dirtyBefore == dirtyAfter && session.recoveryDraft?.id == currentID && session.canKeepRecovery &&
        session.dirty && !session.canClose && !session.isSaving && session.model.sourceRevision == dirtyRevision &&
        session.model.editingGeneration == generation && SourceSelection.sameText(session.model.source, dirtySource) &&
        SourceSelection.sameText(text.string, dirtySource) && text.selectedRange() == dirtyPlan.destination &&
        session.model.documentSelection == dirtyPlan.destination && findSourceView(host) === text && workspace.session === session &&
        window.firstResponder === text, "Conflicted line selection changed settled disk/current recovery/source authority or editor/selection/focus")
    let disk = try Data(contentsOf: file)
    try findRequire(disk == external, "Line selection overwrote the conflicting original")
}

@MainActor func runSourceLineSelectionChecks() async throws {
    try await sourceLineNativeNavigation()
    try await sourceLineWorkspaceRecovery()
    print("PASS native select source lines: actual menu and root validation, full physical ending/BOM-excluded selection, native/model/focus retained, typing undo/redo unchanged; exact refusal state and clean/conflicted whole-workspace bytes/mtime/current checkpoint unchanged after 650 ms")
    print("Passed 1 native source-line selection AppKit group. Authored actions only; OS menus/input/IME, UIKit runtime, VoiceOver, full authoring/security/device/release acceptance remain open.")
}
