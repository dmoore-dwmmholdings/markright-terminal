import AppKit
import Darwin
import Foundation
import SwiftUI

private struct MarkdownCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func markdownStage(_ label: String) {
    FileHandle.standardError.write(Data("[MarkdownChecks] \(label)\n".utf8))
}

@MainActor private func markdownRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw MarkdownCheckFailure(message) }
}

@MainActor private func markdownWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw MarkdownCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func markdownFind(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = markdownFind(child) { return text } }
    return nil
}

@MainActor private final class MarkdownUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor private final class MarkdownFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// Authored menu activation only. NSMenu is never shown and no OS input event
/// or action is sent to another application's responder chain.
@MainActor private func markdownChoose(_ command: MarkdownInsertionCommand, in menu: NSMenu) throws {
    guard let index = menu.items.firstIndex(where: { $0.title == command.title }), menu.items[index].isEnabled else {
        throw MarkdownCheckFailure("Enabled native Markdown command missing: " + command.title)
    }
    menu.performActionForItem(at: index)
}

@MainActor private func checkMarkdownNativeUndo() async throws {
    let literal = "\u{FEFF}Cafe\u{301} 😀\r\nnext\rlast\n"
    var reported = literal
    var reportedRange = SourceSelection.beginning
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = MarkdownUndoDelegate()
    undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let host = NSHostingView(rootView: MacSourceEditor(value: literal, selection: .init(location: 1, length: 6), isEditable: true) {
        reported = $0; reportedRange = $2
    })
    window.contentView = host
    defer { window.contentView = nil; window.delegate = nil; window.close() }
    try await markdownWait("native Markdown source attachment") { host.layoutSubtreeIfNeeded(); return markdownFind(host) != nil }
    guard let text = markdownFind(host) else { throw MarkdownCheckFailure("Native Markdown source missing") }
    try markdownRequire(window.makeFirstResponder(text), "Native Markdown source cannot become first responder")
    let selected = NSRange(location: 1, length: 6)
    text.setSelectedRange(selected)
    let menu = text.makeMarkdownMenu()
    try markdownRequire(menu.items.map(\.title) == MarkdownInsertionCommand.allCases.map(\.title), "Native Markdown menu lost a command")
    try markdownChoose(.bold, in: menu)
    let expected = "\u{FEFF}**Cafe\u{301} **😀\r\nnext\rlast\n"
    try markdownRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                        "Native bold menu transformed source or failed to report its replacement")
    try markdownRequire(text.selectedRange() == NSRange(location: 3, length: 6) && reportedRange == text.selectedRange(),
                        "Native bold menu lost the selected body range")
    try markdownRequire(undoDelegate.manager.canUndo && window.firstResponder === text, "Markdown insertion lost undo or native focus")
    undoDelegate.manager.undo()
    try markdownRequire(SourceSelection.sameText(text.string, literal) && SourceSelection.sameText(reported, literal),
                        "Native undo did not restore exact original Markdown source")
    try markdownRequire(undoDelegate.manager.canRedo, "Markdown insertion has no native redo")
    undoDelegate.manager.redo()
    try markdownRequire(SourceSelection.sameText(text.string, expected) && SourceSelection.sameText(reported, expected),
                        "Native redo did not restore exact inserted Markdown source")
    text.setSelectedRange(NSRange(location: 0, length: 0))
    try markdownChoose(.italic, in: text.makeMarkdownMenu())
    try markdownRequire(text.string.hasPrefix("*text*\u{FEFF}") && text.selectedRange() == NSRange(location: 1, length: 4),
                        "Empty-caret Markdown placeholder was not selected")
    try markdownRequire(!window.isVisible, "Native Markdown menu check showed a window")
    print("PASS native Markdown menu: actual menu action, exact source/BOM/NFD/line endings, selected body/placeholder, native undo/redo and focus")
}

@MainActor private func checkMarkdownStaleActions() async throws {
    markdownStage("stale-action host starting")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = MarkdownUndoDelegate()
    undoDelegate.manager.groupsByEvent = false
    window.delegate = undoDelegate
    let host = NSHostingView(rootView: MacSourceEditor(value: "Cafe\u{301} code", selection: .init(location: 0, length: 5), isEditable: true) { _, _, _ in })
    window.contentView = host
    defer { window.contentView = nil; window.delegate = nil; window.close() }
    try await markdownWait("stale Markdown source attachment") { markdownFind(host) != nil }
    guard let text = markdownFind(host) else { throw MarkdownCheckFailure("Stale Markdown source missing") }
    try markdownRequire(window.makeFirstResponder(text), "Stale-check native focus unavailable")
    let range = NSRange(location: 0, length: 5)
    text.setSelectedRange(range)
    guard let plan = MarkdownInsertionPlan.make(command: .bold, source: text.string, selection: range) else {
        throw MarkdownCheckFailure("Stale-check plan missing")
    }
    let oldMenu = text.makeMarkdownMenu()
    markdownStage("stale-range menu action")
    text.setSelectedRange(NSRange(location: 1, length: 0))
    let unchanged = text.string
    try markdownChoose(.bold, in: oldMenu)
    try markdownRequire(SourceSelection.sameText(text.string, unchanged) && !text.applyMarkdownInsertion(plan),
                        "A stale native menu applied to another selection")
    text.setSelectedRange(range)
    markdownStage("read-only refusal")
    text.isEditable = false
    try markdownRequire(!text.applyMarkdownInsertion(plan), "Read-only Markdown source accepted an edit")
    text.isEditable = true
    let sentinel = MarkdownFocusSentinel(frame: .zero)
    markdownStage("non-source focus refusal")
    host.addSubview(sentinel)
    try markdownRequire(window.makeFirstResponder(sentinel), "Could not prepare non-source focus")
    try markdownRequire(!text.applyMarkdownInsertion(plan) && window.firstResponder === sentinel,
                        "Markdown action edited or took focus from another responder")
    try markdownRequire(window.makeFirstResponder(text), "Could not restore synthetic source focus")
    markdownStage("multiple-selection refusal")
    text.setSelectedRanges([NSValue(range: NSRange(location: 0, length: 1)), NSValue(range: NSRange(location: 7, length: 1))],
                           affinity: .downstream, stillSelecting: false)
    try markdownRequire(text.selectedRanges.count == 2, "Multiple-selection refusal positive control failed")
    guard let multiplePlan = MarkdownInsertionPlan.make(command: .italic, source: text.string, selection: text.selectedRange()) else {
        throw MarkdownCheckFailure("Multiple-selection plan missing")
    }
    try markdownRequire(!text.applyMarkdownInsertion(multiplePlan), "Markdown action silently edited only one of multiple selections")
    text.setSelectedRange(range)
    // AppKit's marked-text input path expects normal event-based undo after
    // the deterministic command checks. Match the existing native IME probe.
    text.breakUndoCoalescing()
    undoDelegate.manager.removeAllActions()
    undoDelegate.manager.groupsByEvent = true
    markdownStage("marked-text positive control")
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: range)
    try markdownRequire(text.hasMarkedText(), "Marked text refusal positive control failed")
    let marked = text.string
    guard let markedPlan = MarkdownInsertionPlan.make(command: .bold, source: marked, selection: text.selectedRange()) else {
        throw MarkdownCheckFailure("Marked-text synthetic plan missing")
    }
    try markdownRequire(!text.applyMarkdownInsertion(markedPlan) && text.hasMarkedText() && SourceSelection.sameText(text.string, marked),
                        "Markdown action disturbed active composition")
    text.unmarkText()
    markdownStage("detached-view refusal")
    text.setSelectedRange(NSRange(location: 0, length: 0))
    guard let detached = MarkdownInsertionPlan.make(command: .inlineCode, source: text.string, selection: text.selectedRange()) else {
        throw MarkdownCheckFailure("Detached synthetic plan missing")
    }
    let beforeDetach = text.string
    window.contentView = nil
    try markdownRequire(text.window == nil && !text.applyMarkdownInsertion(detached) && SourceSelection.sameText(text.string, beforeDetach),
                        "Detached native source accepted a Markdown action")
    try markdownRequire(!window.isVisible, "Stale Markdown check showed a window")
    print("PASS native Markdown refusals: stale menu/range, read-only, non-source focus, multiple selection, marked text and detached view")
}

private struct MarkdownFixture {
    let root: URL
    init() throws {
        guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightMarkdownChecks-" + UUID().uuidString, isDirectory: true)
    }
    func remove() {
        guard root.lastPathComponent.hasPrefix("MarkrightMarkdownChecks-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("MarkrightMarkdownChecks-".count))) != nil else { return }
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Markdown fixture cleanup warning: \(error)\n".utf8)) }
    }
}

@MainActor private func checkMarkdownCollectionRecovery() async throws {
    let fixture = try MarkdownFixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let workspace = MacCollectionWorkspaceModel(store: store)
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Source.mrk")
    guard let session = workspace.session else { throw MarkdownCheckFailure("Markdown synthetic session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let root = window.contentView else { throw MarkdownCheckFailure("Markdown workspace missing") }
    defer { window.delegate = nil; window.contentViewController = nil; window.close() }
    try await Task.sleep(for: .milliseconds(80))
    try await markdownWait("Markdown workspace source") { root.layoutSubtreeIfNeeded(); return !workspace.isBusy && markdownFind(root) != nil }
    guard let text = markdownFind(root) else { throw MarkdownCheckFailure("Markdown workspace source missing") }
    try markdownRequire(window.makeFirstResponder(text), "Markdown workspace cannot focus synthetic source")
    let originalURL = fixture.root.appendingPathComponent("Editing/Source.mrk")
    let external = Data("outside edit\r\n".utf8)
    try external.write(to: originalURL, options: .atomic)
    text.insertText("Re code\r\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await markdownWait("Markdown prefix save error/current recovery") { session.errorMessage != nil && session.canKeepRecovery }
    let initial = text.string
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision
    let baseline = session.document.baseline
    guard let undo = text.undoManager else { throw MarkdownCheckFailure("Markdown workspace undo manager missing") }
    text.breakUndoCoalescing()
    undo.removeAllActions()
    undo.groupsByEvent = false
    text.setSelectedRange(NSRange(location: 3, length: 4))
    try markdownChoose(.inlineCode, in: text.makeMarkdownMenu())
    let formatted = "Re `code`\r\n"
    try await markdownWait("Markdown failed autosave/current complete checkpoint") {
        SourceSelection.sameText(session.model.source, formatted) && session.canKeepRecovery &&
            session.recoveryRevision == session.model.sourceRevision
    }
    try markdownRequire(session.model.sourceRevision > revision && session.model.editingGeneration == generation &&
        workspace.session === session && session.dirty && !session.canClose && session.document.baseline == baseline &&
        session.document.name == "Source.mrk" && SourceSelection.sameText(session.recoveryDraft?.source ?? "", formatted) &&
        session.model.documentSelection == NSRange(location: 4, length: 4) && markdownFind(root) === text && window.firstResponder === text,
        "Markdown ordinary edit lost original identity/source selection/generation or falsely acknowledged save/recovery")
    try markdownRequire(undo.canUndo, "Markdown collection insertion lacks undo")
    undo.undo()
    try await markdownWait("Markdown undo/current recovery") { SourceSelection.sameText(session.model.source, initial) && session.canKeepRecovery }
    try markdownRequire(undo.canRedo, "Markdown collection insertion lacks redo")
    undo.redo()
    try await markdownWait("Markdown redo/current recovery") { SourceSelection.sameText(session.model.source, formatted) && session.canKeepRecovery }
    let disk = try Data(contentsOf: originalURL)
    try markdownRequire(disk == external && session.document.baseline == baseline && !session.canClose,
                        "Markdown edit/undo/redo overwrote the conflicting original or acknowledged it")
    text.onTextStateChanged = nil
    text.delegate = nil
    window.contentViewController = nil
    _ = await session.flush()
    try markdownRequire(!window.isVisible, "Markdown collection check showed a window")
    print("PASS Markdown collection recovery: native inline-code/undo/redo are normal autosaved edits, current full-source recovery, unchanged original baseline/file/session/generation")
}

@MainActor func runMarkdownInsertionChecks() async throws {
    try await checkMarkdownNativeUndo()
    try await checkMarkdownStaleActions()
    try await checkMarkdownCollectionRecovery()
    print("Passed 3 native Markdown insertion AppKit groups. Authored actions only; OS menu/keyboard/IME, iOS runtime, VoiceOver, complete Markdown rendering and release acceptance remain open.")
}
