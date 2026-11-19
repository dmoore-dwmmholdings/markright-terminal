import AppKit
import Darwin
import Foundation
import SwiftUI

private struct OutlineCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
@MainActor private func outlineRequire(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw OutlineCheckFailure(message) }
}
@MainActor private func outlineWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw OutlineCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}
@MainActor private func outlineFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = outlineFind(child) { return text } }
    return nil
}
@MainActor private final class OutlineUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}
@MainActor private final class OutlineFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private func outlineNativeNavigation() async throws {
    let literal = "\u{FEFF}# Cafe\u{301} 😀\r\n```\r\n# hidden\r\n```\r\n## Target\rbody\n"
    var reported = literal
    var reportedRange = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = OutlineUndoDelegate()
    undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 400))
    window.contentView = container
    let host = NSHostingView(rootView: MacSourceEditor(value: literal, selection: SourceSelection.beginning, isEditable: true) {
        reported = $0; reportedRange = $2
    })
    host.frame = container.bounds
    container.addSubview(host)
    let sentinel = OutlineFocusSentinel(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    container.addSubview(sentinel)
    defer {
        if let text = outlineFind(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.makeFirstResponder(nil); undoDelegate.manager.removeAllActions()
        window.contentView = nil; window.delegate = nil; window.close()
    }
    try await outlineWait("outline source attachment") { host.layoutSubtreeIfNeeded(); return outlineFind(host) != nil }
    guard let text = outlineFind(host) else { throw OutlineCheckFailure("Native source missing") }
    try outlineRequire(window.makeFirstResponder(text), "Cannot focus outline source")
    text.setSelectedRange(NSRange(location: literal.utf16.count, length: 0))
    let undo = undoDelegate.manager
    undo.beginUndoGrouping()
    text.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0))
    undo.endUndoGrouping()
    let edited = literal + "typed"
    let menu = text.makeOutlineMenu()
    let report = SourceOutline.make(source: edited)
    try outlineRequire(menu.items.map(\.title) == report.headings.map(\.menuTitle) && menu.items.count == 2,
                       "Native outline menu lost literal heading titles or included fenced body")
    let destination = report.headings[1].range
    let actionName = undo.undoActionName
    menu.performActionForItem(at: 1)
    try outlineRequire(text.selectedRange() == destination && reportedRange == destination &&
        SourceSelection.sameText(text.string, edited) && SourceSelection.sameText(reported, edited) &&
        window.firstResponder === text && text.undoManager === undo && undo.canUndo && undo.undoActionName == actionName,
        "Outline navigation changed source/undo/focus or failed to report exact heading selection")
    undo.undo()
    try outlineRequire(SourceSelection.sameText(text.string, literal), "Outline added a text undo step or lost typing undo")
    undo.redo()
    try outlineRequire(SourceSelection.sameText(text.string, edited), "Outline lost typing redo")

    // Actual retained menu action must not navigate a different selection.
    let staleMenu = text.makeOutlineMenu()
    text.setSelectedRange(NSRange(location: 1, length: 0))
    staleMenu.performActionForItem(at: 1)
    try outlineRequire(text.selectedRange() == NSRange(location: 1, length: 0), "Retained outline ignored stale caret")
    func currentPlan() throws -> SourceNavigationPlan {
        let current = SourceOutline.make(source: text.string)
        guard let heading = current.headings.last, let plan = current.plan(for: heading, selection: text.selectedRange()) else {
            throw OutlineCheckFailure("Current refusal plan missing")
        }
        return plan
    }
    let staleSourcePlan = try currentPlan()
    undo.beginUndoGrouping(); text.insertText("x", replacementRange: .init(location: 1, length: 0)); undo.endUndoGrouping()
    text.setSelectedRange(staleSourcePlan.selection)
    try outlineRequire(!text.applySourceNavigation(staleSourcePlan), "Outline accepted stale source")
    undo.undo()
    text.setSelectedRange(.init(location: 1, length: 0))
    let current = try currentPlan()
    text.isEditable = false
    try outlineRequire(!text.applySourceNavigation(current), "Read-only outline action accepted")
    text.isEditable = true
    try outlineRequire(window.makeFirstResponder(sentinel), "Cannot prepare non-source focus control")
    try outlineRequire(!text.applySourceNavigation(current) && window.firstResponder === sentinel, "Outline stole non-source focus")
    try outlineRequire(window.makeFirstResponder(text), "Cannot restore outline source focus")
    text.setSelectedRanges([NSValue(range: NSRange(location: 1, length: 1)), NSValue(range: NSRange(location: 4, length: 1))],
                           affinity: .downstream, stillSelecting: false)
    try outlineRequire(text.selectedRanges.count == 2, "Multiple-selection outline positive control failed")
    let multiplePlan = try currentPlan()
    try outlineRequire(!text.applySourceNavigation(multiplePlan), "Multiple-selection outline action accepted")
    text.setSelectedRange(.init(location: text.string.utf16.count, length: 0))
    text.breakUndoCoalescing()
    undo.removeAllActions()
    undo.groupsByEvent = true
    text.setMarkedText("仮", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    try outlineRequire(text.hasMarkedText(), "Outline marked-text positive control failed")
    let composingPlan = try currentPlan()
    try outlineRequire(!text.applySourceNavigation(composingPlan) && text.hasMarkedText(), "Outline moved/ended marked text")
    text.unmarkText()
    let detachedPlan = try currentPlan()
    host.removeFromSuperview()
    try outlineRequire(text.window == nil && !text.applySourceNavigation(detachedPlan), "Detached outline action accepted")
}

private struct OutlineSnapshot: Equatable {
    let files: [String]
    let bytes: [String: Data]
    let modified: [String: Date]
    init(root: URL) throws {
        files = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
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

@MainActor private func outlineWorkspaceRecovery() async throws {
    guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
        throw OutlineCheckFailure("Cannot resolve own temporary fixture root")
    }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("MarkrightOutlineChecks-" + UUID().uuidString, isDirectory: true)
    free(physical)
    defer {
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Outline fixture cleanup warning: \(error)\n".utf8)) }
    }
    let store = CollectionStore(root: root)
    let workspace = MacCollectionWorkspaceModel(store: store)
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Outline.md", source: "\u{FEFF}# First\r\nbody\r## Last 😀\n")
    guard let session = workspace.session else { throw OutlineCheckFailure("Outline session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let host = window.contentView else { throw OutlineCheckFailure("Outline workspace missing") }
    defer {
        if let text = outlineFind(host) { text.onTextStateChanged = nil; text.delegate = nil }
        window.delegate = nil; window.contentViewController = nil; window.close()
    }
    try await outlineWait("outline workspace source") { host.layoutSubtreeIfNeeded(); return !workspace.isBusy && outlineFind(host) != nil }
    guard let text = outlineFind(host) else { throw OutlineCheckFailure("Workspace source missing") }
    try await outlineWait("editable outline workspace") { host.layoutSubtreeIfNeeded(); return text.isEditable }
    try outlineRequire(window.makeFirstResponder(text), "Cannot focus workspace source")
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision
    let cleanBytes = try OutlineSnapshot(root: root)
    let cleanOutline = SourceOutline.make(source: text.string)
    let cleanMenu = text.makeOutlineMenu()
    try outlineRequire(cleanOutline.headings.count == 2 && cleanMenu.items.count == 2 &&
        cleanMenu.items.allSatisfy(\.isEnabled), "Clean outline menu is not ready")
    cleanMenu.performActionForItem(at: 1)
    try await Task.sleep(for: .milliseconds(650))
    let cleanAfter = try OutlineSnapshot(root: root)
    try outlineRequire(cleanBytes == cleanAfter && session.model.sourceRevision == revision &&
        text.selectedRange() == cleanOutline.headings[1].range &&
        session.model.editingGeneration == generation && session.model.documentSelection == text.selectedRange(),
        "Clean outline changed disk/source generation or failed to report selection")
    let file = root.appendingPathComponent("Editing/Outline.md")
    let external = Data("outside source stays untouched\r\n".utf8)
    try external.write(to: file, options: .atomic)
    text.setSelectedRange(.init(location: text.string.utf16.count, length: 0))
    text.insertText("unsaved", replacementRange: .init(location: NSNotFound, length: 0))
    try await outlineWait("outline conflicting save/recovery") { session.errorMessage != nil && session.canKeepRecovery && !session.isSaving }
    let checkpoint = session.recoveryDraft?.id, dirtyRevision = session.model.sourceRevision
    let dirtySource = session.model.source, dirtyBytes = try OutlineSnapshot(root: root)
    let outline = SourceOutline.make(source: dirtySource)
    let menu = text.makeOutlineMenu()
    try outlineRequire(menu.items.count == 2, "Conflicted outline lost headings")
    menu.performActionForItem(at: 0)
    try await Task.sleep(for: .milliseconds(650))
    let dirtyAfter = try OutlineSnapshot(root: root)
    try outlineRequire(outlineFind(host) === text && window.firstResponder === text && workspace.session === session &&
        text.selectedRange() == outline.headings[0].range && session.model.documentSelection == text.selectedRange() &&
        session.model.sourceRevision == dirtyRevision && session.model.editingGeneration == generation &&
        SourceSelection.sameText(session.model.source, dirtySource) && session.recoveryDraft?.id == checkpoint &&
        session.dirty && !session.canClose && session.canKeepRecovery && dirtyBytes == dirtyAfter,
        "Conflicted outline changed source/focus/caret authority, disk or settled recovery checkpoint")
    let originalDisk = try Data(contentsOf: file)
    try outlineRequire(originalDisk == external, "Outline overwrote conflicting original")
}

@MainActor func runSourceOutlineChecks() async throws {
    try await outlineNativeNavigation()
    try await outlineWorkspaceRecovery()
    print("PASS native source outline: actual literal menu actions, exact heading selection/focus, typing undo/redo retained, stale-source/caret/read-only/non-source/multiple/marked/detached refusal; clean and conflicted disk/checkpoint unchanged after debounce settlement")
    print("Passed 1 bounded native outline AppKit group. Authored actions only; OS menus/keyboard/IME/VoiceOver, full Markdown outline/parser, iOS runtime and release remain open.")
}
