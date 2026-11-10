import AppKit
import Darwin
import Foundation
import Observation
import SwiftUI

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func stage(_ message: String) {
    FileHandle.standardError.write(Data("[NativeChecks] \(message)\n".utf8))
}

@MainActor private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(message) }
}

@MainActor private func waitUntil(_ message: String, timeout: TimeInterval = 6,
                                 _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw CheckFailure("Timed out: " + message) }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Only this randomly named leaf beneath the physically resolved OS temporary
/// parent is created or removed. No real collections or application support I/O.
private struct Fixture {
    let root: URL

    init() throws {
        let temporary = FileManager.default.temporaryDirectory.path
        guard let physical = temporary.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightNativeChecks-" + UUID().uuidString, isDirectory: true)
    }

    func document(_ collection: String, _ name: String) -> URL {
        root.appendingPathComponent(collection, isDirectory: true).appendingPathComponent(name)
    }

    func remove() {
        guard root.lastPathComponent.hasPrefix("MarkrightNativeChecks-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("MarkrightNativeChecks-".count))) != nil else { return }
        if FileManager.default.fileExists(atPath: root.path) {
            do { try FileManager.default.removeItem(at: root) }
            catch { FileHandle.standardError.write(Data("Fixture cleanup warning: \(error)\n".utf8)) }
        }
    }
}

/// A test-only synchronous actor hold: suspending an async actor method would
/// permit reentrancy and would not hold a queued document operation. Bounded to
/// ten seconds even if a check fails before releasing it.
private final class StoreHold: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entered = false
    var isHeld: Bool { lock.withLock { entered } }
    func block() -> Bool {
        lock.withLock { entered = true }
        return semaphore.wait(timeout: .now() + 10) == .success
    }
    func release() { semaphore.signal() }
}

private extension CollectionStore {
    func holdForNativeCheck(_ hold: StoreHold) -> Bool { hold.block() }
}

@MainActor @Observable private final class SourceProbe {
    var value: String
    var selection = SourceSelection.beginning
    var editable = true
    var label = "Document source"
    var callbacks: [(String, Bool, NSRange)] = []
    init(_ value: String) { self.value = value }
}

@MainActor private struct SourceProbeView: View {
    @Bindable var probe: SourceProbe
    var body: some View {
        MacSourceEditor(value: probe.value, selection: probe.selection, isEditable: probe.editable,
                        accessibilityLabel: probe.label) { value, composing, selection in
            probe.callbacks.append((value, composing, selection))
        }
    }
}

@MainActor private func findSource(_ view: NSView) -> MacSourceTextView? {
    if let text = view as? MacSourceTextView { return text }
    for child in view.subviews {
        if let found = findSource(child) { return found }
    }
    return nil
}

@MainActor private final class SourceUndoDelegate: NSObject, NSWindowDelegate {
    let manager = UndoManager()
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { manager }
}

@MainActor private final class CloseProbeWindow: NSWindow {
    var beforeNextPerformClose: (@MainActor () -> Void)?
    private(set) var interceptedCloses = 0
    override func performClose(_ sender: Any?) {
        if let action = beforeNextPerformClose {
            beforeNextPerformClose = nil
            interceptedCloses += 1
            action()
        }
        super.performClose(sender)
    }
}

@MainActor private func edit(_ session: DocumentSession, _ source: String,
                             composing: Bool = false, selection: NSRange = SourceSelection.beginning) {
    session.model.updateDocumentSource(source, composing: composing,
        generation: session.model.editingGeneration, selection: selection)
}

@MainActor private func checkHostedSource() async throws {
    stage("hosted source: starting")
    let literal = "\u{FEFF}# Source\r\ncafe\u{301} 😀\rraw <script>literal</script>\n[link](https://example.invalid)\n"
    let probe = SourceProbe(literal)
    stage("hosted source: constructing NSHostingView")
    let host = NSHostingView(rootView: SourceProbeView(probe: probe))
    stage("hosted source: constructing NSWindow")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let undoDelegate = SourceUndoDelegate()
    window.delegate = undoDelegate
    window.isReleasedWhenClosed = false
    stage("hosted source: attaching contentView")
    window.contentView = host
    stage("hosted source: calling layoutSubtreeIfNeeded")
    host.layoutSubtreeIfNeeded()
    stage("hosted source: initial layout returned; waiting for NSTextView")
    defer { window.contentView = nil; window.close() }
    try await waitUntil("hosted NSTextView") { findSource(host) != nil }
    guard let text = findSource(host), let coordinator = text.delegate as? MacSourceEditor.Coordinator else {
        throw CheckFailure("Actual representable did not install its source coordinator")
    }
    stage("hosted source: found text/coordinator; waiting for usable geometry")
    try await waitUntil("usable source pane geometry") {
        host.layoutSubtreeIfNeeded()
        guard let scroll = text.enclosingScrollView else { return false }
        return text.bounds.width > 100 && text.bounds.height > 20 &&
            scroll.documentVisibleRect.width > 100 && scroll.documentVisibleRect.height > 20
    }
    stage("hosted source: geometry ready; checking byte and native policies")
    try require(SourceSelection.sameText(text.string, literal), "Hosted editor changed literal UTF-8, BOM, or mixed line endings")
    try require(!text.isRichText && !text.importsGraphics && text.allowsUndo && !text.smartInsertDeleteEnabled,
                "Plain source/undo policies changed")
    try require(!text.isAutomaticQuoteSubstitutionEnabled && !text.isAutomaticDashSubstitutionEnabled &&
                !text.isAutomaticTextReplacementEnabled && !text.isAutomaticSpellingCorrectionEnabled &&
                !text.isContinuousSpellCheckingEnabled && !text.isGrammarCheckingEnabled &&
                !text.isAutomaticLinkDetectionEnabled && !text.isAutomaticDataDetectionEnabled &&
                !text.isAutomaticTextCompletionEnabled, "Source text transformation/detector enabled")
    try require(text.accessibilityLabel() == "Document source", "Source accessibility label changed")
    try require(window.firstResponder === text, "New attached editor did not request initial focus")
    stage("hosted source: policy/focus checks passed; preparing undo")
    let undo = undoDelegate.manager
    undo.groupsByEvent = false
    undo.removeAllActions()
    text.setSelectedRange(NSRange(location: (literal as NSString).length, length: 0))
    undo.beginUndoGrouping()
    stage("hosted source: calling insertText")
    text.insertText("typed -- \"quotes\"", replacementRange: NSRange(location: NSNotFound, length: 0))
    stage("hosted source: insertText returned; ending undo grouping")
    undo.endUndoGrouping()
    try require(SourceSelection.sameText(text.string, literal + "typed -- \"quotes\"") && undo.canUndo,
                "Actual NSTextView insertion changed literal text or failed to register undo")
    undo.undo()
    stage("hosted source: undo returned; checking source and selection")
    try require(SourceSelection.sameText(text.string, literal), "Actual NSTextView undo failed to restore exact source bytes")
    let range = (literal as NSString).range(of: "cafe\u{301}")
    MacSourceEditor.restoreSelection(range, in: text)
    try require(text.selectedRange() == range, "Valid UTF-16 source selection was not restored")
    window.makeFirstResponder(nil)
    stage("hosted source: resigned responder; testing equal-byte apply")
    MacSourceEditor.apply(text, value: literal, selection: SourceSelection.beginning, isEditable: true)
    try require(text.selectedRange() == range && window.firstResponder !== text,
                "Equal-byte update changed the caret or reclaimed focus")
    MacSourceEditor.restoreSelection(NSRange(location: (literal as NSString).length + 1, length: 0), in: text)
    try require(text.selectedRange() == SourceSelection.beginning, "Invalid range was not refused")

    // Canonical Unicode equality must not skip an actual source-byte change.
    MacSourceEditor.apply(text, value: "café", selection: SourceSelection.beginning, isEditable: true)
    MacSourceEditor.apply(text, value: "cafe\u{301}", selection: NSRange(location: 5, length: 0), isEditable: true)
    try require(text.string.utf8.elementsEqual("cafe\u{301}".utf8), "Canonical equivalence hid a changed byte sequence")
    stage("hosted source: restoring native input focus and automatic undo grouping")
    try require(window.makeFirstResponder(text), "Marked-text check could not restore its input responder")
    text.breakUndoCoalescing()
    undo.removeAllActions()
    undo.groupsByEvent = true
    stage("hosted source: setting marked text")
    text.setMarkedText("仮", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
    stage("hosted source: marked text set; testing apply preservation")
    try require(text.hasMarkedText(), "Programmatic marked-text positive control failed")
    let markedSource = text.string, markedSelection = text.selectedRange()
    MacSourceEditor.apply(text, value: "must not replace", selection: SourceSelection.beginning, isEditable: false)
    try require(text.hasMarkedText() && SourceSelection.sameText(text.string, markedSource) &&
                text.selectedRange() == markedSelection && text.isEditable, "Update disturbed active marked text")
    try require(probe.callbacks.contains { $0.1 }, "Coordinator did not report composition")
    coordinator.finishComposition(text)
    stage("hosted source: composition finished; updating read-only representable")
    try require(!text.hasMarkedText() && probe.callbacks.last?.1 == false,
                "Composition teardown did not report its final source state")
    if let final = probe.callbacks.last {
        try require(SourceSelection.sameText(final.0, text.string) && final.2 == text.selectedRange(),
                    "Final coordinator source/range diverged")
    }

    // Exercise actual representable updateNSView, including the editable-to-
    // read-only accessibility label, rather than only testing static helpers.
    probe.value = literal
    probe.editable = false
    probe.label = "Recovery source preview, read only"
    try await waitUntil("read-only representable update") {
        !text.isEditable && text.accessibilityLabel() == probe.label && SourceSelection.sameText(text.string, literal)
    }
    stage("hosted source: read-only update returned")
    try require(text.isSelectable && !text.isRichText && !text.isAutomaticLinkDetectionEnabled,
                "Recovery preview gained rich text or URL detectors")
    guard let storage = text.textStorage else { throw CheckFailure("Recovery preview text storage missing") }
    var hasLinkAttribute = false
    storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length), options: []) { value, _, stop in
        if value != nil {
            hasLinkAttribute = true
            stop.pointee = true
        }
    }
    try require(!hasLinkAttribute, "Plain recovery preview installed an attributed URL")
    try require(!window.isVisible, "Source check showed its synthetic window")
    print("PASS hosted source: literal bytes, actual insert/undo, plain policies, UTF-16 caret, one-shot focus, marked-text preservation and read-only label")
}

@MainActor private func checkCreateEditSaveAs() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let model = MacCollectionWorkspaceModel(store: store)
    let first = await model.createCollection("Work")
    let second = await model.createCollection("Archive")
    try require(first && second, "Could not create synthetic collections")
    await model.selectCollection("Work")
    let created = await model.createDocument(name: "source.md")
    guard let created, let session = model.session else { throw CheckFailure("Created document was not adopted") }
    try require(created.name == "source.md" && session.model.sourceMode, "Native workspace did not enter complete source mode")
    let source = "\u{FEFF}# Saved\r\nUnicode 😀 cafe\u{301}\rtrailing\n"
    let caret = NSRange(location: 2, length: 3)
    edit(session, source, selection: caret)
    session.scheduleSave()
    let flushed = await session.flush()
    try require(flushed, "Source edits did not flush")
    let original = try await store.open(collection: "Work", name: "source.md")
    try require(SourceSelection.sameText(original.source, source), "Saved source bytes changed")
    try require(model.prepareSaveAsDialog(), "Save As preparation failed")
    let wrongExtension = await model.saveAs(collection: "Archive", name: "wrong.mrk")
    try require(wrongExtension == nil && session.document.name == "source.md", "Save As accepted an extension change")
    let receipt = await model.saveAs(collection: "Archive", name: "copy.md")
    model.resumeAfterSaveAsDialog()
    try require(receipt?.name == "copy.md" && model.session === session && model.selectedCollection == "Archive",
                "Save As failed to retain its receipt/session")
    try require(SourceSelection.sameText(session.model.source, source) && session.model.documentSelection == caret,
                "Save As changed source or caret")
    edit(session, source + "new destination\n")
    let copied = await session.flush()
    try require(copied, "New destination edits failed to flush")
    let unchanged = try await store.open(collection: "Work", name: "source.md")
    let changed = try await store.open(collection: "Archive", name: "copy.md")
    try require(SourceSelection.sameText(unchanged.source, source) && SourceSelection.sameText(changed.source, source + "new destination\n"),
                "Save As wrote later edits to the wrong destination")
    print("PASS model create, exact-source save, Save As extension/refusal, caret and destination ownership")
}

@MainActor private func checkRecoveryReuse() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let model = MacCollectionWorkspaceModel(store: store)
    _ = await model.createCollection("Recovery")
    _ = await model.createDocument(name: "original.mrk", source: "original\n")
    guard let session = model.session else { throw CheckFailure("Recovery session missing") }
    try Data("external version\n".utf8).write(to: fixture.document("Recovery", "original.mrk"), options: .atomic)
    edit(session, "current recovery\n")
    let flushed = await session.flush()
    try require(!flushed && session.canKeepRecovery, "Conflict failed to preserve an acknowledged recovery")
    let firstClose = Task { await model.prepareToClose() }
    try await waitUntil("recovery close choice") { model.recoveryCloseRequested }
    let concurrent = await model.prepareToClose()
    try require(!concurrent, "Concurrent close replaced a pending decision")
    edit(session, "newer than the displayed recovery\n")
    model.resolveRecoveryClose(keepRecovery: true)
    let staleAccepted = await firstClose.value
    try require(!staleAccepted && model.session === session, "Stale recovery acknowledgement discarded newer source")
    let secondClose = Task { await model.prepareToClose() }
    try await waitUntil("fresh recovery close choice") { model.recoveryCloseRequested }
    model.resolveRecoveryClose(keepRecovery: true)
    let accepted = await secondClose.value
    try require(accepted && model.session == nil && model.canCloseNow && model.selectedCollection == "Recovery",
                "Confirmed recovery close did not safely release the session")
    guard let draft = model.recoveries.first else { throw CheckFailure("Confirmed draft was not retained in the reused inbox") }
    let inventory = try await store.recoveries()
    try require(inventory.drafts.contains { $0.id == draft.id }, "Recovery close deleted its journal")
    let restored = await model.restore(draft, collection: "Recovery", name: "recovered.mrk")
    try require(restored != nil && model.session?.document.name == "recovered.mrk" &&
                SourceSelection.sameText(model.session?.model.source ?? "", "newer than the displayed recovery\n"),
                "Reusing the workspace could not restore its acknowledged draft")
    let external = try await store.open(collection: "Recovery", name: "original.mrk")
    try require(SourceSelection.sameText(external.source, "external version\n"), "Recovery replaced the original")
    print("PASS conflict recovery, concurrent/stale close refusal, journal retention, workspace reuse and new-copy restore")
}

@MainActor private func checkLateCreateReceipt() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let model = MacCollectionWorkspaceModel(store: store)
    _ = await model.createCollection("Late")
    _ = await model.createDocument(name: "current.mrk", source: "baseline\n")
    guard let current = model.session else { throw CheckFailure("Late-edit session missing") }
    let hold = StoreHold()
    let holder = Task { await store.holdForNativeCheck(hold) }
    defer { hold.release() }
    try await waitUntil("store actor hold") { hold.isHeld }
    let creating = Task { await model.createDocument(name: "committed.mrk", source: "new file\n") }
    try await waitUntil("queued create") { model.isBusy }
    // The clean session's initial flush needs no store call. Let that same-
    // actor path finish while the document create remains held at the store.
    try await Task.sleep(for: .milliseconds(40))
    edit(current, "late current edits\n")
    try Data("outside change\n".utf8).write(to: fixture.document("Late", "current.mrk"), options: .atomic)
    hold.release()
    let held = await holder.value
    let receipt = await creating.value
    try require(held && receipt?.name == "committed.mrk", "Queued creation did not return its committed receipt")
    try require(model.session === current && SourceSelection.sameText(current.model.source, "late current edits\n"),
                "Post-I/O adoption discarded newer conflicted source")
    try require(model.lastCommittedDocument?.name == "committed.mrk" && model.documents.contains("committed.mrk"),
                "Blocked adoption lost the committed receipt or list entry")
    let saved = try await store.open(collection: "Late", name: "committed.mrk")
    try require(SourceSelection.sameText(saved.source, "new file\n") && current.canKeepRecovery,
                "Committed new file or late-source recovery was lost")
    print("PASS actor-held I/O: late conflicted edits retained, committed receipt returned and new file listable")
}

@MainActor private func checkInvisibleCloseGuards() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let store = CollectionStore(root: fixture.root)
    let model = MacCollectionWorkspaceModel(store: store)
    _ = await model.createCollection("Close")
    _ = await model.createDocument(name: "guard.mrk", source: "baseline\n")
    guard let session = model.session else { throw CheckFailure("Close-check session missing") }
    let controller = MacCollectionWorkspaceWindowController(model: model)
    guard let original = controller.window else { throw CheckFailure("Native controller window missing") }
    let hosted = original.contentViewController
    original.contentViewController = nil
    original.delegate = nil
    let window = CloseProbeWindow(contentRect: original.frame, styleMask: original.styleMask,
                                  backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = hosted
    controller.window = window
    window.delegate = controller
    defer { window.orderOut(nil); window.contentView = nil }
    // The real hosting view can start its initial refresh while being mounted.
    try await Task.sleep(for: .milliseconds(80))
    try await waitUntil("initial workspace refresh") { !model.isBusy }
    try require(!window.isVisible && window.delegate === controller, "Controller showed a window or lost its owned delegate")
    edit(session, "composition in progress\n", composing: true)
    try require(!controller.windowShouldClose(window), "Window close bypassed composition")
    try await Task.sleep(for: .milliseconds(30))
    let composingQuit = await controller.prepareToTerminate()
    try require(!composingQuit && model.session === session && !model.canCloseNow,
                "Quit preparation bypassed composition")
    edit(session, "finished composition\n")
    let finished = await session.flush()
    try require(finished, "Finished synthetic composition could not save")
    let prepared = await controller.prepareToTerminate()
    try require(prepared && model.canCloseNow, "Safe invisible quit preparation failed")
    edit(session, "newer than quit preparation\n")
    try require(!model.canCloseNow && !model.releaseSafelyClosedSession() && model.session === session,
                "Fresh close/quit guard ignored a newer revision")
    window.beforeNextPerformClose = {
        edit(session, "composition after close authorization\n", composing: true)
    }
    try require(!controller.windowShouldClose(window), "Initial close did not defer for its asynchronous flush")
    try await waitUntil("edit injected after close authorization") { window.interceptedCloses == 1 && !model.isBusy }
    try require(!controller.isClosed && model.session === session && session.model.composing && !window.isVisible,
                "The real delegate's final authorization gate discarded a newer composing edit")
    edit(session, "committed after refused authorized close\n")
    try require(!controller.windowShouldClose(window), "Retry close failed to defer for its current flush")
    try await waitUntil("guarded invisible window close") { controller.isClosed }
    let saved = try await store.open(collection: "Close", name: "guard.mrk")
    try require(SourceSelection.sameText(saved.source, "committed after refused authorized close\n") &&
                model.session == nil && model.canCloseNow && !window.isVisible,
                "Actual close failed to flush current source and release only its safe session")
    print("PASS invisible native window: owned delegate, composition refusal, injected post-authorization edit refusal, fresh quit guard and actual safe-session release")
}

@MainActor private func runChecks() async throws {
    stage("runChecks entered")
    try require(NSApplication.shared.activationPolicy() == .prohibited, "Probe activation policy must remain prohibited")
    try require(MacCollectionWorkspaceManager.shared.controller == nil, "Probe touched the real workspace manager")
    try await checkHostedSource()
    stage("starting create/edit/Save As checks")
    try await checkCreateEditSaveAs()
    stage("starting recovery reuse checks")
    try await checkRecoveryReuse()
    stage("starting actor-held I/O check")
    try await checkLateCreateReceipt()
    stage("starting invisible close guards")
    try await checkInvisibleCloseGuards()
    try await runSavedSearchChecks()
    try require(!NSApplication.shared.isActive && NSApplication.shared.windows.allSatisfy { !$0.isVisible },
                "Offscreen checks activated the application or showed a window")
    try require(MacCollectionWorkspaceManager.shared.controller == nil, "Probe opened the real collection root")
    print("Passed 8 focused native AppKit check groups. No real keyboard/IME, VoiceOver, full parser/preview, production storage/security or release acceptance claimed.")
}

@main private enum NativeCollectionChecks {
    @MainActor static func main() {
        stage("main entered; creating NSApplication")
        let app = NSApplication.shared
        stage("NSApplication created; prohibiting activation")
        app.setActivationPolicy(.prohibited)
        stage("activation prohibited; scheduling main-actor check task")
        Task { @MainActor in
            stage("main-actor check task entered")
            do { try await runChecks(); exit(0) }
            catch {
                FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        stage("entering NSApplication.run")
        app.run()
    }
}
