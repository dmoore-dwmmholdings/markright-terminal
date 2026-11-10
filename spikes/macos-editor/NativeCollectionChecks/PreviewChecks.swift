import AppKit
import Darwin
import Foundation
import SwiftUI

private struct PreviewCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func previewRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw PreviewCheckFailure(message) }
}

@MainActor private func previewWait(_ label: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw PreviewCheckFailure("Timed out: " + label) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func previewFindSource(_ root: NSView) -> MacSourceTextView? {
    if let text = root as? MacSourceTextView { return text }
    for child in root.subviews { if let text = previewFindSource(child) { return text } }
    return nil
}

@MainActor private func previewScrollViews(_ root: NSView) -> [NSScrollView] {
    ((root as? NSScrollView).map { [$0] } ?? [])
        + root.subviews.flatMap { previewScrollViews($0) }
}

/// Public accessibility getters on this test-owned view tree only. No AX
/// process access, VoiceOver settings, UI actions or cross-application lookup.
@MainActor private func previewAXNodes(_ root: Any) -> [(node: AnyObject, id: String?, label: String?, title: String?, value: String?)] {
    var pending: [Any] = [root]
    // Public AppKit utility flattens ignored local containers. It only queries
    // this fixture subtree; no application root or AX setting is changed.
    pending.append(contentsOf: NSAccessibility.unignoredChildrenForOnlyChild(from: root))
    var seen = Set<ObjectIdentifier>()
    var result: [(AnyObject, String?, String?, String?, String?)] = []
    var visited = 0
    while let item = pending.popLast(), visited < 1024 {
        guard let object = item as? any NSObjectProtocol,
              seen.insert(ObjectIdentifier(object as AnyObject)).inserted else { continue }
        visited += 1
        func get(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        let value = get("accessibilityValue")
        result.append((object as AnyObject, get("accessibilityIdentifier") as? String,
                       get("accessibilityLabel") as? String, get("accessibilityTitle") as? String,
                       (value as? String) ?? (value as? NSAttributedString)?.string))
        // LIFO: visit semantic SwiftUI AX children before the larger raw native
        // hierarchy. Duplicate raw/AX references do not consume the node budget.
        if let view = item as? NSView { pending.append(contentsOf: view.subviews) }
        pending.append(contentsOf: get("accessibilityChildren") as? [Any] ?? [])
    }
    return result
}

@MainActor private func previewPanelText(_ root: NSView) -> String? {
    guard let panel = previewAXNodes(root).first(where: { $0.id == "live-preview-panel" }) else { return nil }
    return previewAXNodes(panel.node).flatMap { [$0.label, $0.title, $0.value].compactMap { $0 } }.joined(separator: "\n")
}

@MainActor private func previewOpenDocument(_ name: String, root: NSView) -> Bool {
    // AppKit describes visible push-button text as Title; Label is a separate
    // nullable description. Require the open state on that same element.
    previewAXNodes(root).contains { ($0.label == name || $0.title == name) && $0.value == "Open" }
}

private struct PreviewFixture {
    let root: URL
    init() throws {
        guard let physical = FileManager.default.temporaryDirectory.path.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightPreviewChecks-" + UUID().uuidString, isDirectory: true)
    }
    func document(_ name: String) -> URL { root.appendingPathComponent("Editing").appendingPathComponent(name) }
    func remove() {
        guard root.lastPathComponent.hasPrefix("MarkrightPreviewChecks-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("MarkrightPreviewChecks-".count))) != nil else { return }
        do { if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) } }
        catch { FileHandle.standardError.write(Data("Preview fixture cleanup warning: \(error)\n".utf8)) }
    }
}

private struct PreviewDiskSnapshot: Equatable {
    let paths: [String]
    let bytes: [String: Data]
    let modified: [String: Date]
    init(root: URL) throws {
        paths = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        var bytes: [String: Data] = [:]
        var modified: [String: Date] = [:]
        for path in paths {
            let url = root.appendingPathComponent(path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if attributes[.type] as? FileAttributeType == .typeRegular { bytes[path] = try Data(contentsOf: url) }
            modified[path] = attributes[.modificationDate] as? Date
        }
        self.bytes = bytes
        self.modified = modified
    }
}

@MainActor private final class PreviewUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor func runSourcePreviewChecks() async throws {
    let fixture = try PreviewFixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let workspace = MacCollectionWorkspaceModel(store: store)
    let original = "**ACTIVE_SOURCE**\r\n\nInactive **bold** [label](https://example.invalid)\r\n<script>literal()</script>\r\n![asset](remote.png)\r\n```swift\r\nlet value = 1\r\n```\r\n| A | B |\r\n| --- | --- |\r\n| x | y |\r\n"
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "First.md", source: original)
    guard let session = workspace.session else { throw PreviewCheckFailure("Preview test session missing") }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let undoDelegate = PreviewUndoDelegate()
    window.delegate = undoDelegate
    // Match the passing search probe's direct host inside a common AppKit
    // container, with no NSHostingController appearance/AX claim.
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 760))
    window.contentView = container
    let root = NSHostingView(rootView: MacCollectionWorkspace(model: workspace, allowsSourceCopyExportPresentation: false))
    root.frame = container.bounds
    root.autoresizingMask = [.width, .height]
    container.addSubview(root)
    defer {
        if let currentRoot = window.contentView, let text = previewFindSource(currentRoot) {
            text.onTextStateChanged = nil; text.delegate = nil
        }
        window.delegate = nil
        window.contentView = nil
        window.close()
    }
    try await Task.sleep(for: .milliseconds(80))
    try await previewWait("source workspace attachment") {
        root.layoutSubtreeIfNeeded(); return !workspace.isBusy && previewFindSource(root) != nil
    }
    guard let source = previewFindSource(root), let undo = source.undoManager else { throw PreviewCheckFailure("Preview source/undo missing") }
    try previewRequire(!workspace.showsSourcePreview && previewPanelText(root) == nil, "Preview was enabled automatically")
    try previewRequire(window.makeFirstResponder(source), "Cannot prepare preview source focus")
    source.setSelectedRange(NSRange(location: 0, length: 0))
    source.breakUndoCoalescing()
    undo.removeAllActions()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    source.insertText("typed ", replacementRange: NSRange(location: NSNotFound, length: 0))
    undo.endUndoGrouping()
    let saved = await session.flush()
    try previewRequire(saved && undo.canUndo, "Synthetic edit did not save while retaining native undo")
    let edited = "typed " + original
    let generation = session.model.editingGeneration, revision = session.model.sourceRevision
    let caret = source.selectedRange(), baseline = session.document.baseline
    let diskBefore = try PreviewDiskSnapshot(root: fixture.root)
    let baselineScrolls = Set(previewScrollViews(root).map(ObjectIdentifier.init))
    var renderFailures: [String] = []
    @MainActor func observe(_ label: String, _ condition: () -> Bool) async {
        do { try await previewWait(label, condition) }
        catch { renderFailures.append(label) }
    }
    @MainActor func waitForPane(_ visible: Bool) async throws {
        try await previewWait(visible ? "preview native pane attached" : "preview native pane detached") {
            root.layoutSubtreeIfNeeded()
            let views = previewScrollViews(root)
            let ids = Set(views.map(ObjectIdentifier.init))
            let added = views.filter { !baselineScrolls.contains(ObjectIdentifier($0)) }
            if !visible { return ids == baselineScrolls }
            return baselineScrolls.isSubset(of: ids) && added.count == 1 &&
                added[0].bounds.width > 0 && added[0].bounds.height > 0
        }
    }
    workspace.showsSourcePreview = true
    try await waitForPane(true)
    do {
        try await previewWait("rendered partial preview") {
            root.layoutSubtreeIfNeeded()
            return previewPanelText(root)?.contains("Inactive bold label") == true && previewOpenDocument("First.md", root: root)
        }
    } catch {
        let nodes = previewAXNodes(root)
        let textMatched = previewPanelText(root)?.contains("Inactive bold label") == true
        FileHandle.standardError.write(Data("[PreviewChecks] enabled=\(workspace.showsSourcePreview), sourceFrame=\(source.frame), rootFrame=\(root.frame), nodes=\(nodes.count), panelFound=\(nodes.contains { $0.id == "live-preview-panel" }), previewTextMatched=\(textMatched), openMarker=\(previewOpenDocument("First.md", root: root))\n".utf8))
        for node in nodes.filter({ $0.id != nil || $0.label != nil || $0.title != nil || $0.value != nil }).prefix(90) {
            FileHandle.standardError.write(Data("[PreviewChecks] id=\(node.id ?? "nil") label=\(String((node.label ?? "nil").prefix(180))) title=\(String((node.title ?? "nil").prefix(180))) value=\(String((node.value ?? "nil").prefix(180)))\n".utf8))
        }
        renderFailures.append("rendered partial preview/open-document marker")
    }
    if !(previewPanelText(root)?.contains("typed **ACTIVE_SOURCE**") == true &&
        previewPanelText(root)?.contains("<script>literal()</script>") == true &&
        previewPanelText(root)?.contains("![asset](remote.png)") == true) {
        renderFailures.append("rendered active/unsupported literal source")
    }
    let hasSemanticObservation = renderFailures.isEmpty
    if !hasSemanticObservation {
        FileHandle.standardError.write(Data("[PreviewChecks] Rendering gate remains failed; continue independent native data-retention checks. Dependent AX assertions are unrun.\n".utf8))
    }
    for _ in 0..<2 {
        workspace.showsSourcePreview = false
        try await waitForPane(false)
        if hasSemanticObservation { await observe("preview hidden") { previewPanelText(root) == nil } }
        workspace.showsSourcePreview = true
        try await waitForPane(true)
        if hasSemanticObservation { await observe("preview shown again") { previewPanelText(root)?.contains("Inactive bold label") == true } }
    }
    let diskAfter = try PreviewDiskSnapshot(root: fixture.root)
    try previewRequire(workspace.session === session && previewFindSource(root) === source && window.firstResponder === source &&
        source.selectedRange() == caret && source.undoManager === undo && undo.canUndo &&
        session.model.editingGeneration == generation && session.model.sourceRevision == revision &&
        SourceSelection.sameText(source.string, edited) && SourceSelection.sameText(session.model.source, edited) &&
        session.document.baseline == baseline && diskBefore == diskAfter,
        "Preview toggles changed native identity/caret/focus/undo/source/generation or disk state")
    undo.undo()
    try await previewWait("native undo with preview") { SourceSelection.sameText(session.model.source, original) }
    undo.redo()
    try await previewWait("native redo with preview") { SourceSelection.sameText(session.model.source, edited) }
    _ = await session.flush()
    source.breakUndoCoalescing()
    undo.removeAllActions()
    undo.groupsByEvent = true
    source.setSelectedRange(NSRange(location: 0, length: 0))
    source.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0),
                         replacementRange: NSRange(location: 0, length: 0))
    try previewRequire(source.hasMarkedText() && session.model.composing, "Preview composition positive control failed")
    try await previewWait("composition projection pause") {
        SourcePreviewProjection.make(source: session.model.source, selection: session.model.documentSelection, composing: session.model.composing).state == .composing
    }
    if hasSemanticObservation { await observe("composition preview pause") { previewPanelText(root)?.contains("paused") == true } }
    try previewRequire(previewFindSource(root) === source && source.hasMarkedText() && window.firstResponder === source,
                       "Preview pause recreated source, ended marked text or moved focus")
    source.unmarkText()
    try await previewWait("preview projection resumes") {
        !session.model.composing && SourcePreviewProjection.make(source: session.model.source, selection: session.model.documentSelection, composing: false).state == .ready
    }
    if hasSemanticObservation { await observe("preview resumes") { previewPanelText(root)?.contains("Inactive bold label") == true } }
    _ = await session.flush()
    let external = Data("outside source remains unchanged\r\n".utf8)
    try external.write(to: fixture.document("First.md"), options: .atomic)
    source.setSelectedRange(NSRange(location: source.string.utf16.count, length: 0))
    source.insertText("Unsaved **LATEST**\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    try await previewWait("conflicting autosave/current recovery/live projection") {
        session.errorMessage != nil && session.canKeepRecovery &&
            SourcePreviewProjection.make(source: session.model.source, selection: session.model.documentSelection, composing: false).rows.contains { String($0.display.characters).contains("Unsaved LATEST") }
    }
    if hasSemanticObservation { await observe("unsaved rendered preview") { previewPanelText(root)?.contains("Unsaved LATEST") == true } }
    let dirtyValue = session.model.source, dirtyRevision = session.model.sourceRevision
    let recoveryID = session.recoveryDraft?.id, dirtyCaret = source.selectedRange()
    let conflictedSnapshot = try PreviewDiskSnapshot(root: fixture.root)
    workspace.showsSourcePreview = false
    try await waitForPane(false)
    if hasSemanticObservation { await observe("conflicted preview hidden") { previewPanelText(root) == nil } }
    workspace.showsSourcePreview = true
    try await waitForPane(true)
    if hasSemanticObservation { await observe("conflicted preview shown") { previewPanelText(root)?.contains("Unsaved LATEST") == true } }
    // Layout must not schedule a deferred save/recovery rewrite. Let the
    // session's 300ms debounce settle before Save As can cancel it.
    try await Task.sleep(for: .milliseconds(650))
    let conflictAfter = try PreviewDiskSnapshot(root: fixture.root)
    try previewRequire(previewFindSource(root) === source && window.firstResponder === source &&
        source.selectedRange() == dirtyCaret && session.model.sourceRevision == dirtyRevision &&
        session.model.editingGeneration == generation && session.recoveryDraft?.id == recoveryID &&
        session.canKeepRecovery && session.dirty && !session.canClose && conflictedSnapshot == conflictAfter &&
        SourceSelection.sameText(session.model.source, dirtyValue),
        "Conflicted preview changed source/focus/caret or acknowledged/rewrote recovery/original")
    let copied = await workspace.saveAs(collection: "Editing", name: "Recovered.md")
    try previewRequire(copied != nil && session.canClose, "Synthetic Save As could not preserve the conflicted source")
    _ = await workspace.createDocument(name: "Other.md", source: "Other **document**\n")
    try await previewWait("native source/model follow new document") {
        workspace.session?.document.name == "Other.md" &&
            previewFindSource(root).map { SourceSelection.sameText($0.string, "Other **document**\n") } == true
    }
    if hasSemanticObservation {
        await observe("preview and open marker follow new document") {
            previewPanelText(root)?.contains("Other **document**") == true && previewOpenDocument("Other.md", root: root)
                && previewPanelText(root)?.contains("ACTIVE_SOURCE") == false && !previewOpenDocument("First.md", root: root)
        }
    }
    guard let current = workspace.session else { throw PreviewCheckFailure("Changed document session missing") }
    let currentProjection = SourcePreviewProjection.make(source: current.model.source, selection: current.model.documentSelection, composing: false)
    try previewRequire(currentProjection.rows.contains { $0.source.contains("Other **document**") } &&
        !currentProjection.rows.contains { $0.source.contains("ACTIVE_SOURCE") }, "Projection retained old document state")
    let originalDisk = try Data(contentsOf: fixture.document("First.md"))
    try previewRequire(originalDisk == external && !window.isVisible && !NSApplication.shared.isActive,
                       "Preview workflow overwrote the conflicting original or showed a window")
    _ = await current.flush()
    print("PASS native preview data retention: real pane toggles, stable source identity/caret/focus/undo, marked-text retention, unchanged settled disk/recovery, unsaved/live projection, Save As and fresh native source/document projection")
    guard renderFailures.isEmpty else {
        throw PreviewCheckFailure("Rendered preview observation remains unverified: " + renderFailures.joined(separator: "; "))
    }
    print("PASS native preview observation: inactive styling, active/unsupported literal rows, composition caption, unsaved content and current-document Open marker")
    print("Passed 2 native companion preview AppKit groups. Authored input/local AX only; full inline editor/parser, controller-host/OS input/IME/VoiceOver, iOS runtime and release remain open.")
}
