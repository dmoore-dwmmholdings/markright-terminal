import AppKit
import Darwin
import Foundation
import SwiftUI

private struct SavedSearchCheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func savedSearchRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw SavedSearchCheckFailure(message) }
}

private func savedSearchStage(_ message: String) {
    FileHandle.standardError.write(Data("[SavedSearchChecks] \(message)\n".utf8))
}

@MainActor private func savedSearchWait(_ message: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(6)
    while !condition() {
        guard Date() < deadline else { throw SavedSearchCheckFailure("Timed out: " + message) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private struct SavedSearchFixture {
    let root: URL
    init() throws {
        let temporary = FileManager.default.temporaryDirectory.path
        guard let physical = temporary.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightSavedSearchChecks-" + UUID().uuidString, isDirectory: true)
    }
    func document(_ collection: String, _ name: String) -> URL {
        root.appendingPathComponent(collection, isDirectory: true).appendingPathComponent(name)
    }
    func remove() {
        let prefix = "MarkrightSavedSearchChecks-"
        guard root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil else { return }
        if FileManager.default.fileExists(atPath: root.path) {
            do { try FileManager.default.removeItem(at: root) }
            catch { FileHandle.standardError.write(Data("Search fixture cleanup warning: \(error)\n".utf8)) }
        }
    }
}

private struct SavedSearchSnapshot: Equatable {
    let paths: [String]
    let files: [String: Data]
    let modifications: [String: Date]
    init(root: URL) throws {
        paths = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        var data: [String: Data] = [:]
        var dates: [String: Date] = [:]
        for path in paths {
            let url = root.appendingPathComponent(path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if attributes[.type] as? FileAttributeType == .typeRegular {
                data[path] = try Data(contentsOf: url)
            }
            if let date = attributes[.modificationDate] as? Date { dates[path] = date }
        }
        files = data
        modifications = dates
    }
}

@MainActor private final class SavedSearchFocusSentinel: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor private final class SavedSearchUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor private func savedSearchFind<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
    if let found = root as? T { return found }
    for child in root.subviews {
        if let found = savedSearchFind(type, in: child) { return found }
    }
    return nil
}

/// Read the local hosting view's accessibility elements only. There is no AX
/// process control, keyboard automation, URL action, or cross-app lookup.
@MainActor private func savedSearchAccessibleText(_ root: NSView, diagnose: Bool = false) -> String {
    var pending: [Any] = [root]
    var seen = Set<ObjectIdentifier>()
    var strings: [String] = []
    var diagnostics: [String] = []
    var inspected = 0
    while let item = pending.popLast(), inspected < 512 {
        inspected += 1
        // SwiftUI can vend public accessibility protocol objects/proxies that
        // inherit neither NSView nor the NSAccessibilityElement concrete class.
        // Read only these three documented object-valued accessibility getters.
        guard let node = item as? any NSObjectProtocol else {
            if diagnose, diagnostics.count < 64 {
                diagnostics.append("dropped non-NSObjectProtocol node: \(String(reflecting: type(of: item)))")
            }
            continue
        }
        guard seen.insert(ObjectIdentifier(node as AnyObject)).inserted else { continue }
        let labelSelector = NSSelectorFromString("accessibilityLabel")
        let valueSelector = NSSelectorFromString("accessibilityValue")
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        let label = node.responds(to: labelSelector) ? node.perform(labelSelector)?.takeUnretainedValue() as? String : nil
        let value = node.responds(to: valueSelector) ? node.perform(valueSelector)?.takeUnretainedValue() : nil
        var children = node.responds(to: childrenSelector)
            ? (node.perform(childrenSelector)?.takeUnretainedValue() as? [Any] ?? []) : []
        if let view = item as? NSView { children.append(contentsOf: view.subviews) }
        if let label { strings.append(label) }
        if let text = value as? String { strings.append(text) }
        if let text = value as? NSAttributedString { strings.append(text.string) }
        if diagnose, diagnostics.count < 64 {
            let text = (value as? String) ?? (value as? NSAttributedString)?.string
            let valueDescription = text.map { String($0.prefix(200)).debugDescription }
                ?? value.map { "<\(String(reflecting: type(of: $0)))>" } ?? "nil"
            let labelDescription = label.map { String($0.prefix(160)).debugDescription } ?? "nil"
            diagnostics.append("\(String(reflecting: type(of: node))) label=\(labelDescription) value=\(valueDescription) children=\(children.count)")
        }
        pending.append(contentsOf: children)
    }
    if diagnose {
        savedSearchStage("literal-preview AX diagnostic: inspected=\(inspected), unique=\(seen.count), pending=\(pending.count), diagnosticRows<=64")
        for diagnostic in diagnostics { savedSearchStage(diagnostic) }
    }
    return strings.joined(separator: "\n")
}

@MainActor private func savedSearchWindow<Content: View>(_ content: Content, height: CGFloat = 700)
    throws -> (NSWindow, NSHostingView<Content>, SavedSearchFocusSentinel) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: height))
    let sentinel = SavedSearchFocusSentinel(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    container.addSubview(sentinel)
    window.contentView = container
    try savedSearchRequire(window.makeFirstResponder(sentinel), "Could not install the private non-text focus sentinel")
    let host = NSHostingView(rootView: content)
    host.frame = container.bounds
    host.autoresizingMask = [.width, .height]
    container.addSubview(host)
    host.layoutSubtreeIfNeeded()
    return (window, host, sentinel)
}

@MainActor private func checkSavedSearchQueryInput() async throws {
    savedSearchStage("literal native query starting")
    let literal = "\u{FEFF}plain -- \"quoted\"\r\ncafe\u{301} 😀\rnext\n"
    var callbacks: [(String, Bool)] = []
    let (window, host, sentinel) = try savedSearchWindow(
        CollectionSearchQueryEditor(value: literal) { callbacks.append(($0, $1)) }.frame(height: 100), height: 140)
    let undoDelegate = SavedSearchUndoDelegate()
    window.delegate = undoDelegate
    defer { window.contentView = nil; window.close() }
    try await savedSearchWait("native query attachment") { savedSearchFind(CollectionSearchQueryTextView.self, in: host) != nil }
    guard let text = savedSearchFind(CollectionSearchQueryTextView.self, in: host),
          let coordinator = text.delegate as? CollectionSearchQueryEditor.Coordinator else {
        throw SavedSearchCheckFailure("Native query coordinator missing")
    }
    try await savedSearchWait("native query layout") { host.layoutSubtreeIfNeeded(); return text.bounds.width > 100 && text.bounds.height > 20 }
    try savedSearchRequire(window.firstResponder === sentinel, "Query attachment stole focus")
    try savedSearchRequire(SourceSelection.sameText(text.string, literal), "Query changed literal BOM/line endings/Unicode")
    try savedSearchRequire(!text.isRichText && !text.importsGraphics && text.allowsUndo &&
        !text.smartInsertDeleteEnabled && !text.isAutomaticQuoteSubstitutionEnabled &&
        !text.isAutomaticDashSubstitutionEnabled && !text.isAutomaticTextReplacementEnabled &&
        !text.isAutomaticSpellingCorrectionEnabled && !text.isContinuousSpellCheckingEnabled &&
        !text.isGrammarCheckingEnabled && !text.isAutomaticLinkDetectionEnabled &&
        !text.isAutomaticDataDetectionEnabled && !text.isAutomaticTextCompletionEnabled && text.enabledTextCheckingTypes == 0,
        "Native query literal-input policy changed")
    try savedSearchRequire(text.accessibilityIdentifier() == "collection-search-query" && text.accessibilityLabel() == "Saved-source search query",
                           "Query accessibility identity changed")
    let caret = NSRange(location: 2, length: 3)
    text.setSelectedRange(caret)
    CollectionSearchQueryEditor.apply(text, value: literal, isEditable: true)
    try savedSearchRequire(text.selectedRange() == caret && window.firstResponder === sentinel,
                           "Equal-byte query update reset caret or focus")
    try savedSearchRequire(window.makeFirstResponder(text), "Could not prepare the native query input responder")
    text.setSelectedRange(NSRange(location: (literal as NSString).length, length: 0))
    text.insertText("typed -- \"literal\"\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    try savedSearchRequire(SourceSelection.sameText(text.string, literal + "typed -- \"literal\"\n"), "Actual query insertText transformed punctuation/newlines")
    text.breakUndoCoalescing()
    undoDelegate.manager.removeAllActions()
    undoDelegate.manager.groupsByEvent = true
    savedSearchStage("literal native query setting marked text with valid input preconditions")
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
    try savedSearchRequire(text.hasMarkedText() && callbacks.contains { $0.1 }, "Query marked-text positive control failed")
    let marked = text.string, markedCaret = text.selectedRange()
    CollectionSearchQueryEditor.apply(text, value: "stale replacement", isEditable: false)
    try savedSearchRequire(text.hasMarkedText() && SourceSelection.sameText(text.string, marked) &&
        text.selectedRange() == markedCaret && text.isEditable, "Stale query apply disturbed marked text")
    coordinator.finishComposition(text)
    try savedSearchRequire(!text.hasMarkedText() && callbacks.last?.1 == false &&
        SourceSelection.sameText(callbacks.last?.0 ?? "", text.string), "Finishing active query composition lost its final value")
    text.setMarkedText("残", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
    try savedSearchRequire(text.hasMarkedText(), "Retired-callback marked-text positive control failed")
    let retiringValue = text.string
    let callbackCount = callbacks.count
    coordinator.retire()
    coordinator.report(text)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
    coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: text))
    coordinator.finishComposition(text)
    text.onTextStateChanged?()
    try savedSearchRequire(coordinator.isRetired && callbacks.count == callbackCount && text.hasMarkedText() &&
        SourceSelection.sameText(text.string, retiringValue), "Retired query coordinator changed state or finished dying composition")
    text.onTextStateChanged = nil
    text.delegate = nil
    text.unmarkText()
    try savedSearchRequire(!window.isVisible, "Native query check showed its window")
    print("PASS saved search query: actual literal input/policies, no autofocus, caret, active composition callback and retired-callback refusal")
}

@MainActor private func checkSavedSearchPanel() async throws {
    savedSearchStage("expanded search panel starting")
    let fixture = try SavedSearchFixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    try await store.createCollection("Saved")
    try await store.createCollection("Other")
    let literal = "<script>alert('literal')</script> [link](https://example.invalid)\nneedle\n"
    _ = try await store.createDocument(collection: "Saved", name: "Literal.md", source: literal)
    _ = try await store.createDocument(collection: "Saved", name: "Plain.mrk", source: "unrelated source\n")
    let before = try SavedSearchSnapshot(root: fixture.root)
    let model = CollectionSearchModel(store: store)
    var opened: [String] = []
    let (window, host, sentinel) = try savedSearchWindow(
        CollectionSearchPanel(model: model, collection: "Saved", initiallyExpanded: true) { opened.append($0) })
    let undoDelegate = SavedSearchUndoDelegate()
    window.delegate = undoDelegate
    defer { model.cancel(); window.contentView = nil; window.close() }
    try await savedSearchWait("expanded panel scope and query") {
        model.collection == "Saved" && savedSearchFind(CollectionSearchQueryTextView.self, in: host) != nil
    }
    guard let query = savedSearchFind(CollectionSearchQueryTextView.self, in: host) else {
        throw SavedSearchCheckFailure("Expanded panel did not host its native query")
    }
    try await savedSearchWait("expanded panel layout") { host.layoutSubtreeIfNeeded(); return query.bounds.width > 100 && query.bounds.height > 20 }
    try savedSearchRequire(model.report == nil && !model.isSearching && window.firstResponder === sentinel,
                           "Expanding the panel searched or took focus automatically")
    model.query = "<script>"
    try await savedSearchWait("query value delivery") { SourceSelection.sameText(query.string, model.query) }
    try savedSearchRequire(window.makeFirstResponder(query), "Could not prepare query focus for retention check")
    let caret = NSRange(location: 1, length: 3)
    query.setSelectedRange(caret)
    model.run()
    try await savedSearchWait("saved-source panel report") { !model.isSearching && model.report != nil }
    guard let report = model.report else { throw SavedSearchCheckFailure("Panel report missing") }
    try savedSearchRequire(report.hits.count == 1 && report.hits[0].name == "Literal.md" &&
        SourceSelection.sameText(report.hits[0].preview, literal) && report.issues.isEmpty,
        "Saved-source report did not preserve the script-like literal preview")
    do {
        try await savedSearchWait("literal preview in rendered accessibility content") {
            host.layoutSubtreeIfNeeded()
            return savedSearchAccessibleText(host).contains("<script>alert('literal')</script>")
        }
    } catch {
        _ = savedSearchAccessibleText(host, diagnose: true)
        throw error
    }
    try savedSearchRequire(query.selectedRange() == caret && window.firstResponder === query &&
        savedSearchFind(CollectionSearchQueryTextView.self, in: host) === query && opened.isEmpty,
        "Rendering results changed query view/caret/focus or opened a document automatically")
    model.query = "needle"
    try savedSearchRequire(model.report == nil && !model.isSearching, "Query edit retained an old report or searched automatically")
    host.rootView = CollectionSearchPanel(model: model, collection: "Other", initiallyExpanded: true) { opened.append($0) }
    try await savedSearchWait("changed collection scope") { model.collection == "Other" }
    try savedSearchRequire(model.report == nil && !model.isSearching && opened.isEmpty,
                           "Scope change retained old results or opened a file")
    let after = try SavedSearchSnapshot(root: fixture.root)
    try savedSearchRequire(before == after, "Standalone search changed saved files or created metadata")
    try savedSearchRequire(!window.isVisible, "Expanded search panel showed its window")
    print("PASS saved search panel: actual expanded layout/literal preview, explicit queries, query focus/caret retention, scope invalidation and read-only disk snapshot")
}

@MainActor private func disposeSavedSearchWorkspace(_ controller: MacCollectionWorkspaceWindowController,
                                                   session: DocumentSession) async {
    let retiringCoordinator: MacSourceEditor.Coordinator?
    if let root = controller.window?.contentView,
       let text = savedSearchFind(MacSourceTextView.self, in: root) {
        retiringCoordinator = text.delegate as? MacSourceEditor.Coordinator
        text.onTextStateChanged = nil
        text.delegate = nil
    } else { retiringCoordinator = nil }
    // Join/cancel this synthetic session's normal save work before deleting its
    // unique fixture. This cleanup is outside the retention assertions.
    _ = await session.flush()
    retiringCoordinator?.onChange = { _, _, _ in }
    // Remove the presentation anchor before asking the model to retire this
    // synthetic session; cleanup must not present a recovery-choice sheet.
    controller.window?.contentViewController = nil
    if session.canClose {
        controller.model.releaseSafelyClosedSession()
    } else if session.canKeepRecovery {
        var closeFinished = false
        let closing = Task {
            let result = await controller.model.prepareToClose()
            closeFinished = true
            return result
        }
        do {
            try await savedSearchWait("synthetic recovery-close cleanup") {
                controller.model.recoveryCloseRequested || closeFinished
            }
        } catch { savedSearchStage("cleanup close wait: \(error)") }
        if controller.model.recoveryCloseRequested { controller.model.resolveRecoveryClose(keepRecovery: true) }
        _ = await closing.value
    }
    // The approved recovery close normally detached the session already. Also
    // silence this test-owned retiring coordinator if an earlier check failed.
    retiringCoordinator?.onChange = { _, _, _ in }
    controller.window?.delegate = nil
    controller.window?.close()
}

@MainActor private func checkSavedSearchSourceRetention() async throws {
    savedSearchStage("source/error-header/search retention starting")
    let fixture = try SavedSearchFixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let workspace = MacCollectionWorkspaceModel(store: store)
    _ = await workspace.createCollection("Editing")
    _ = await workspace.createDocument(name: "Active.md")
    guard let session = workspace.session else { throw SavedSearchCheckFailure("Active source session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: workspace)
    do {
        guard let window = controller.window, let root = window.contentView else {
            throw SavedSearchCheckFailure("Private native workspace window missing")
        }
        try await Task.sleep(for: .milliseconds(80))
        try await savedSearchWait("source workspace layout") {
            root.layoutSubtreeIfNeeded()
            return !workspace.isBusy && savedSearchFind(MacSourceTextView.self, in: root) != nil
        }
        guard let source = savedSearchFind(MacSourceTextView.self, in: root) else { throw SavedSearchCheckFailure("Real source view missing") }
        try savedSearchRequire(window.makeFirstResponder(source), "Could not prepare initial source responder")
        let external = Data("external saved needle\n".utf8)
        try external.write(to: fixture.document("Editing", "Active.md"), options: .atomic)
        source.insertText("Re", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await savedSearchWait("first normal autosave error/current recovery") {
            session.errorMessage != nil && session.canKeepRecovery && SourceSelection.sameText(session.model.source, "Re")
        }
        try savedSearchRequire(savedSearchFind(MacSourceTextView.self, in: root) === source && window.firstResponder === source,
                               "Save-error header replaced the source view or lost its focus")
        guard let documentUndo = source.undoManager else {
            throw SavedSearchCheckFailure("Real workspace source has no undoManager after native insertion")
        }
        try savedSearchRequire(documentUndo.canUndo, "Real workspace source cannot undo native insertion")
        // Deliberately no tap, responder call, selection reset or explicit flush
        // between these inserts: the visible save-error header must be inert.
        source.insertText(" suffix UNIQUE_UNSAVED_TOKEN", replacementRange: NSRange(location: NSNotFound, length: 0))
        let expected = "Re suffix UNIQUE_UNSAVED_TOKEN"
        try await savedSearchWait("continued input/current recovery without refocus") {
            SourceSelection.sameText(session.model.source, expected) && session.errorMessage != nil &&
                session.canKeepRecovery && session.recoveryRevision == session.model.sourceRevision
        }
        try savedSearchRequire(savedSearchFind(MacSourceTextView.self, in: root) === source && window.firstResponder === source,
                               "Continued input after the error header lost its view/focus")
        let sessionID = session.id, generation = session.model.editingGeneration, revision = session.model.sourceRevision
        let caret = source.selectedRange()
        let snapshot = try SavedSearchSnapshot(root: fixture.root)
        let search = CollectionSearchModel(store: store)
        search.setCollection("Editing")
        search.query = "needle"
        search.run()
        try await savedSearchWait("saved needle search") { !search.isSearching && search.report != nil }
        try savedSearchRequire(search.report?.hits.map(\.name) == ["Active.md"], "Search did not find the external saved source")
        search.query = "UNIQUE_UNSAVED_TOKEN"
        search.run()
        try await savedSearchWait("unsaved token search") { !search.isSearching && search.report != nil }
        try savedSearchRequire(search.report?.hits.isEmpty == true && search.report?.issues.isEmpty == true,
                               "Saved-source search included unsaved editor text")
        search.cancel()
        try savedSearchRequire(workspace.session === session && session.id == sessionID &&
            session.model.editingGeneration == generation && session.model.sourceRevision == revision &&
            SourceSelection.sameText(session.model.source, expected) && SourceSelection.sameText(source.string, expected) &&
            source.selectedRange() == caret && savedSearchFind(MacSourceTextView.self, in: root) === source &&
            window.firstResponder === source && source.undoManager === documentUndo && documentUndo.canUndo,
            "Search changed the active source/session/generation/caret/view/focus or undo history")
        let finalBytes = try Data(contentsOf: fixture.document("Editing", "Active.md"))
        let finalSnapshot = try SavedSearchSnapshot(root: fixture.root)
        try savedSearchRequire(finalBytes == external && finalSnapshot == snapshot,
                               "Saved-source search changed the conflicting original or recovery metadata")
        try savedSearchRequire(!window.isVisible, "Source retention check showed its native workspace")
        await disposeSavedSearchWorkspace(controller, session: session)
    } catch {
        await disposeSavedSearchWorkspace(controller, session: session)
        throw error
    }
    print("PASS saved search source retention: native input across save-error headers, current recovery, saved-only hits and unchanged source/caret/focus/undo/disk")
}

@MainActor func runSavedSearchChecks() async throws {
    try savedSearchRequire(NSApplication.shared.activationPolicy() == .prohibited,
                           "Saved-source checks require prohibited activation")
    try savedSearchRequire(MacCollectionWorkspaceManager.shared.controller == nil,
                           "Saved-source checks must not open the real workspace manager")
    try await checkSavedSearchQueryInput()
    try await checkSavedSearchPanel()
    try await checkSavedSearchSourceRetention()
    try savedSearchRequire(!NSApplication.shared.isActive && NSApplication.shared.windows.allSatisfy { !$0.isVisible },
                           "Saved-source checks activated the app or showed a window")
    try savedSearchRequire(MacCollectionWorkspaceManager.shared.controller == nil,
                           "Saved-source checks touched the real collection root")
    print("Passed 3 saved-source search AppKit groups. Authored native input only; no OS keyboard/IME, iOS runtime, VoiceOver, WebKit or production acceptance claimed.")
}
