import AppKit
import CoreTransferable
import Darwin
import Foundation
import UniformTypeIdentifiers

private struct SourceCopyCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func exportRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw SourceCopyCheckFailure(message) }
}

@MainActor private func exportWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw SourceCopyCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Only this fresh UUID leaf under the trusted physical OS temporary parent is
/// written/removed. No customer source, app support, pasteboard or provider UI.
private struct SourceCopyFixture {
    let root: URL
    init() throws {
        guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightSourceCopyChecks-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func remove() {
        guard root.lastPathComponent.hasPrefix("MarkrightSourceCopyChecks-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("MarkrightSourceCopyChecks-".count))) != nil else { return }
        do { try FileManager.default.removeItem(at: root) }
        catch { FileHandle.standardError.write(Data("Export fixture cleanup warning: \(error)\n".utf8)) }
    }
}

@MainActor private func exportFindSource(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews {
        if let text = exportFindSource(child) { return text }
    }
    return nil
}

@available(macOS 15.2, *)
@MainActor private func checkSourceCopyTransfer() async throws {
    let fixture = try SourceCopyFixture()
    defer { fixture.remove() }
    let literal = "\u{FEFF}Cafe\u{301} 😀\r\n[asset](image.png)\r<script>literal()</script>\n"
    try exportRequire(SourceCopyTransfer.importedContentTypes().isEmpty, "Source copy acquired an import representation")
    for (name, type) in [("Cafe\u{301}.MD", UTType.markdownSourceCopy), ("Note.MrK", UTType.markrightSourceCopy)] {
        let session = DocumentSession(document: StoredDocument(collection: "Synthetic", name: name,
                                                               source: "original", baseline: Data("original".utf8))) { document, source in
            StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8))
        }
        session.model.showSource()
        session.model.updateDocumentSource(literal, composing: false, generation: session.model.editingGeneration)
        let payload = SourceCopyTransfer(snapshot: try SourceCopySnapshot(session: session))
        session.model.updateDocumentSource("later unsaved edit", composing: false, generation: session.model.editingGeneration)
        try exportRequire(payload.contentType == type && payload.exportedContentTypes() == [type], "Conditional source type changed")
        try exportRequire(payload.suggestedFilename?.utf8.elementsEqual(name.utf8) == true, "Suggested filename bytes changed")
        let bytes = try await payload.exported(as: type)
        try exportRequire(bytes == Data(literal.utf8), "Real Transferable serialization changed source bytes")
        var refusedWrongType = false
        do { _ = try await payload.exported(as: .png) } catch { refusedWrongType = true }
        try exportRequire(refusedWrongType, "Source copy exported an unrelated representation")
        var refusedImport = false
        do { _ = try await SourceCopyTransfer(importing: bytes, contentType: type) } catch { refusedImport = true }
        try exportRequire(refusedImport, "Export-only adapter accepted imported source")
        let directory = fixture.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let output = try await payload.export(to: directory, contentType: type)
        try exportRequire(output.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
                          "Transferable wrote outside the private destination")
        let disk = try Data(contentsOf: output)
        try exportRequire(disk == Data(literal.utf8), "Real Transferable file export changed exact bytes")
        try exportRequire(session.dirty && !session.canClose && session.document.source == "original" &&
            session.document.baseline == Data("original".utf8) && session.model.source == "later unsaved edit",
            "Transferable serialization acknowledged/rebound or replaced the original")
    }
    print("PASS source copy transfer: actual conditioned DataRepresentation bytes/file serialization, literal BOM/NFD/line endings, no importing and immutable unsaved snapshot")
}

@MainActor private func checkSourceCopyWorkspace() async throws {
    let fixture = try SourceCopyFixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root.appendingPathComponent("Collections", isDirectory: true))
    let workspace = MacCollectionWorkspaceModel(store: store)
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Original.mrk")
    guard let session = workspace.session else { throw SourceCopyCheckFailure("Synthetic session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace, allowsSourceCopyExportPresentation: false)
    guard let window = controller.window, let root = window.contentView else {
        throw SourceCopyCheckFailure("Private source copy workspace missing")
    }
    defer { window.delegate = nil; window.contentViewController = nil; window.close() }
    try await Task.sleep(for: .milliseconds(80))
    try await exportWait("private source attachment") { root.layoutSubtreeIfNeeded(); return !workspace.isBusy && exportFindSource(root) != nil }
    guard let source = exportFindSource(root) else { throw SourceCopyCheckFailure("Real source editor missing") }
    try exportRequire(window.makeFirstResponder(source), "Could not prepare synthetic source input")
    let originalURL = fixture.root.appendingPathComponent("Collections/Editing/Original.mrk")
    let external = Data("external conflicting source\n".utf8)
    try external.write(to: originalURL, options: .atomic)
    source.insertText("Re", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await exportWait("failed autosave with current recovery") { session.errorMessage != nil && session.canKeepRecovery }
    source.insertText(" source copy -- \"literal\"\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await exportWait("continued native input checkpoint") { session.canKeepRecovery && session.recoveryRevision == session.model.sourceRevision }
    let value = session.model.source, revision = session.model.sourceRevision, generation = session.model.editingGeneration
    let caret = source.selectedRange(), recoveryID = session.recoveryDraft?.id, baseline = session.document.baseline
    guard let undo = source.undoManager else { throw SourceCopyCheckFailure("Native source undo manager missing") }
    try exportRequire(undo.canUndo && workspace.beginSourceCopyExport(), "Could not begin source copy with undo history")
    guard let first = workspace.sourceCopyExport.request else { throw SourceCopyCheckFailure("Source copy request missing") }
    try exportRequire(first.data == Data(value.utf8) && !workspace.canCloseNow && !workspace.prepareSaveAsDialog(),
                      "Pending export failed to preserve snapshot or guard close/Save As")
    let closed = await workspace.prepareToClose()
    let created = await workspace.createDocument(name: "ShouldNotExist.mrk")
    await workspace.selectCollection("Other")
    try exportRequire(!closed && created == nil && workspace.session === session && workspace.selectedCollection == "Editing",
                      "Pending export permitted close or navigation")
    try exportRequire(!controller.windowShouldClose(window), "Native close delegate allowed pending export")
    let manager = MacCollectionWorkspaceManager(controller: controller)
    var terminationReplies = 0
    let delegate = MarkrightMacApplicationDelegate(workspaceManager: manager) { _, _ in terminationReplies += 1 }
    try exportRequire(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel,
                      "App quit queued work for a pending export")
    try exportRequire(workspace.sourceCopyExport.finish(id: first.id, result: .success(())), "Matching completion was refused")
    try await Task.sleep(for: .milliseconds(50))
    try exportRequire(terminationReplies == 0, "Refused quit scheduled a late termination reply")
    var idleReply: Bool?
    let idleDelegate = MarkrightMacApplicationDelegate(workspaceManager: MacCollectionWorkspaceManager()) { _, safe in idleReply = safe }
    try exportRequire(idleDelegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater,
                      "Idle app quit failed to defer for its current-state check")
    try exportRequire(idleDelegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel,
                      "Duplicate app quit replaced a pending termination decision")
    try await exportWait("inert idle termination reply") { idleReply != nil }
    try exportRequire(idleReply == true, "Idle app quit failed its injected safe reply")
    let retained: [(String, Bool)] = [
        ("close stays refused", !workspace.canCloseNow), ("dirty", session.dirty), ("recovery current", session.canKeepRecovery),
        ("recovery token", session.recoveryDraft?.id == recoveryID), ("baseline", session.document.baseline == baseline),
        ("name", session.document.name == "Original.mrk"), ("revision", session.model.sourceRevision == revision),
        ("generation", session.model.editingGeneration == generation), ("model source", SourceSelection.sameText(session.model.source, value)),
        ("native source", SourceSelection.sameText(source.string, value)), ("view identity", exportFindSource(root) === source),
        ("caret", source.selectedRange() == caret), ("focus", window.firstResponder === source),
        ("undo identity", source.undoManager === undo), ("undo available", undo.canUndo),
    ]
    for (label, passed) in retained where !passed {
        FileHandle.standardError.write(Data("[SourceCopyChecks] retention failed: \(label)\n".utf8))
    }
    try exportRequire(!workspace.canCloseNow && session.dirty && session.canKeepRecovery &&
        session.recoveryDraft?.id == recoveryID && session.document.baseline == baseline && session.document.name == "Original.mrk" &&
        session.model.sourceRevision == revision && session.model.editingGeneration == generation &&
        SourceSelection.sameText(session.model.source, value) && SourceSelection.sameText(source.string, value) &&
        exportFindSource(root) === source && source.selectedRange() == caret && window.firstResponder === source &&
        source.undoManager === undo && undo.canUndo,
        "Source copy success changed dirty recovery/original identity/source/view/caret/focus/undo")
    for cancelled in [true, false] {
        try exportRequire(workspace.beginSourceCopyExport(), "Retry did not capture a new source copy")
        guard let request = workspace.sourceCopyExport.request else { throw SourceCopyCheckFailure("Retry request missing") }
        try exportRequire(!workspace.sourceCopyExport.finish(id: first.id, result: .success(())), "Old completion affected retry")
        if cancelled { try exportRequire(workspace.sourceCopyExport.cancel(id: request.id), "Cancel failed") }
        else { try exportRequire(workspace.sourceCopyExport.finish(id: request.id, result: .failure(CocoaError(.fileWriteUnknown))), "Failure completion failed") }
    }
    let disk = try Data(contentsOf: originalURL)
    try exportRequire(disk == external && session.dirty && !session.canClose && session.recoveryDraft?.id == recoveryID,
                      "Export callbacks changed the conflicting original/recovery")
    // Test-owned teardown with a pending immutable request and presentation
    // explicitly disabled: no OS save panel can appear during this probe.
    try exportRequire(workspace.beginSourceCopyExport(), "Teardown request missing")
    let retiring = workspace.sourceCopyExport.request!.id
    source.onTextStateChanged = nil
    source.delegate = nil
    window.contentViewController = nil
    try exportRequire(workspace.sourceCopyExport.cancel(id: retiring), "Detached request failed to cancel")
    _ = await session.flush()
    try exportRequire(!window.isVisible && !NSApplication.shared.isActive, "Source copy probe showed or activated a window")
    print("PASS source copy workspace: guarded navigation/close/quit, native source/caret/focus/undo and conflicted recovery retained, stale/cancel/error callbacks and pending teardown with OS picker disabled")
}

@MainActor func runSourceCopyChecks() async throws {
    guard #available(macOS 15.2, *) else {
        throw SourceCopyCheckFailure("Transferable inspection probe needs macOS 15.2; product APIs retain macOS 14 minimum")
    }
    try await checkSourceCopyTransfer()
    try await checkSourceCopyWorkspace()
    print("Passed 2 source copy AppKit/Transferable groups. No OS exporter/provider, iOS runtime, keyboard/IME, VoiceOver or release acceptance claimed.")
}
