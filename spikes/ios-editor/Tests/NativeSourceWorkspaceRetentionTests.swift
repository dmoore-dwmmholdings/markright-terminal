import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import MarkrightEditorSpike

private actor WorkspaceRetentionRecovery {
    struct Observation: Sendable {
        let checkpoints: [RecoveryDraft]
        let savedSources: [String]
        let completedCount: Int
        let createCount: Int
    }
    private let sessionID = UUID()
    private var checkpoints: [RecoveryDraft] = []
    private var savedSources: [String] = []
    private var completedCount = 0
    private var createCount = 0

    func checkpoint(_ document: StoredDocument, source: String) -> RecoveryDraft {
        let draft = RecoveryDraft(sessionID: sessionID, collection: document.collection, name: document.name,
                                  source: source, baseline: document.baseline)
        checkpoints.append(draft)
        return draft
    }

    func save(_ document: StoredDocument, source: String) throws -> StoredDocument {
        savedSources.append(source)
        throw CollectionStoreError.conflict
    }

    func complete(_ draft: RecoveryDraft) { completedCount += 1 }

    func create(_ collection: String, _ name: String, _ source: String) throws -> StoredDocument {
        createCount += 1
        throw CocoaError(.fileWriteNoPermission)
    }

    func observation() -> Observation {
        Observation(checkpoints: checkpoints, savedSources: savedSources,
                    completedCount: completedCount, createCount: createCount)
    }
}

/// SOURCE-ONLY CANDIDATE: UNCOMPILED / UNRUN.
/// This hosts the actual workspace, using authored native insertText calls. It
/// does not establish OS keyboard input, undo/redo, IME or rendered-pixel proof.
@MainActor final class NativeSourceWorkspaceRetentionTests: XCTestCase {
    private enum GateFailure: Error { case failed(String) }
    private static let maximumNodes = 2048
    private static let maximumAncestorDepth = 64

    private struct HeaderObservation {
        var failedSave = false
        var acknowledgedRecovery = false
        var closeRecovery = false
        var retrySave = false
        var visitedNodes = 0
        var isPresent: Bool { failedSave && acknowledgedRecovery && closeRecovery && retrySave }
    }

    private func require(_ condition: Bool, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            XCTFail(message, file: file, line: line)
            throw GateFailure.failed(message)
        }
    }

    private func poll(_ message: String, settledFor: Duration = .zero, condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(4))
        var readySince: ContinuousClock.Instant?
        for _ in 0..<400 {
            try Task.checkCancellation()
            if try condition() {
                let since = readySince ?? clock.now
                readySince = since
                if clock.now >= since.advanced(by: settledFor) { return }
            } else { readySince = nil }
            if clock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(false, message)
    }

    private func sourceViews(in root: UIView) throws -> [SourceTextView] {
        var pending = [root]
        var visited = Set<ObjectIdentifier>()
        var result: [SourceTextView] = []
        while let view = pending.popLast() {
            guard visited.insert(ObjectIdentifier(view)).inserted else { continue }
            try require(visited.count <= Self.maximumNodes, "Owned view traversal exceeded its node bound")
            if let source = view as? SourceTextView, source.accessibilityIdentifier == "document-source-editor" {
                result.append(source)
            }
            try require(pending.count + view.subviews.count <= Self.maximumNodes, "Owned view traversal exceeded its pending bound")
            pending.append(contentsOf: view.subviews)
        }
        return result
    }

    private func outerScrollView(of source: SourceTextView, window: UIWindow) throws -> UIScrollView {
        var ancestor = source.superview
        for _ in 0..<Self.maximumAncestorDepth {
            guard let view = ancestor else { break }
            if let scroll = view as? UIScrollView, scroll.window === window { return scroll }
            ancestor = view.superview
        }
        try require(false, "The actual source editor has no bounded attached outer scroll view")
        throw GateFailure.failed("Outer scroll view unavailable")
    }

    private func headerObservation(in root: UIView, window: UIWindow) throws -> HeaderObservation {
        try require(root.window === window && !window.isHidden, "Header observation requires the owned attached host")
        let visibleFrame = UIAccessibility.convertToScreenCoordinates(window.bounds, in: window)
        var pending: [NSObject] = [root]
        var visited = Set<ObjectIdentifier>()
        var result = HeaderObservation()
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            try require(visited.count <= Self.maximumNodes, "Owned accessibility traversal exceeded its node bound")
            if let view = node as? UIView, view.window !== window || view.isHidden || view.alpha <= 0 { continue }
            if node.accessibilityElementsHidden { continue }
            let identifier = (node as? any UIAccessibilityIdentification)?.accessibilityIdentifier
            let label = node.accessibilityLabel ?? ""
            let frame = node.accessibilityFrame
            let hasVisibleFrame = frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
                && frame.intersects(visibleFrame)
            let attached = (node as? UIView).map { $0.window === window && !$0.isHidden && $0.alpha > 0 } ?? true
            if attached && hasVisibleFrame {
                if identifier == "document-save-status" && label.hasPrefix("Could not save.") { result.failedSave = true }
                if identifier == "document-recovery-status" && label == "Recovery copy saved on this device" { result.acknowledgedRecovery = true }
                if identifier == "close-with-recovery" && label == "Close with recovery copy" && node.accessibilityTraits.contains(.button) { result.closeRecovery = true }
                if identifier == "retry-save" && label == "Retry save" && node.accessibilityTraits.contains(.button) { result.retrySave = true }
            }

            // Public accessibility containers are necessary here: SwiftUI text
            // and buttons need not be UILabel/UIControl subviews. Every root of
            // this bounded traversal comes from the owned host, never the app.
            var children: [NSObject] = []
            if let view = node as? UIView { children.append(contentsOf: view.subviews) }
            if let elements = node.accessibilityElements {
                try require(elements.count <= Self.maximumNodes, "Owned accessibility child array exceeded its bound")
                children.append(contentsOf: elements.compactMap { $0 as? NSObject })
            }
            let count = node.accessibilityElementCount()
            if count != NSNotFound && count >= 0 {
                try require(count <= Self.maximumNodes, "Owned accessibility container exceeded its bound")
                for index in 0..<count {
                    if let child = node.accessibilityElement(at: index) as? NSObject { children.append(child) }
                }
            }
            try require(pending.count + children.count <= Self.maximumNodes, "Owned accessibility traversal exceeded its pending bound")
            pending.append(contentsOf: children)
        }
        result.visitedNodes = visited.count
        return result
    }

    private func requireRetained(_ source: SourceTextView, host: UIView, window: UIWindow,
                                 coordinatorID: ObjectIdentifier, undoID: ObjectIdentifier,
                                 session: DocumentSession, model: EditorModel,
                                 generation: Int, expected: String, original: StoredDocument) throws {
        let current = try sourceViews(in: host)
        try require(current.count == 1 && current.first === source, "Header relayout replaced or detached the native source object")
        try require(source.window === window && source.isFirstResponder, "Header relayout lost native source attachment or input focus")
        let coordinator = try XCTUnwrap(source.delegate as? NativeSourceEditor.Coordinator)
        try require(ObjectIdentifier(coordinator) == coordinatorID, "Header relayout replaced the real coordinator")
        let undo = try XCTUnwrap(source.undoManager)
        try require(ObjectIdentifier(undo) == undoID && undo.canUndo, "Header relayout lost the native undo manager or its edit history")
        try require(session.model === model && model.editingGeneration == generation && model.sourceMode,
                    "Header relayout changed model identity, source mode or callback generation")
        try require(SourceSelection.sameText(source.text, expected) && SourceSelection.sameText(model.source, expected),
                    "Native source and the real coordinator/model report do not match expected bytes")
        let caret = NSRange(location: expected.utf16.count, length: 0)
        try require(source.selectedRange == caret && model.documentSelection == caret, "Header relayout changed the native/model caret")
        try require(source.markedTextRange == nil && !model.composing, "The fixture unexpectedly entered composition")
        try require(session.dirty && !session.canClose && session.canKeepRecovery,
                    "The failed original save lost dirty/current-recovery authority")
        try require(session.document.collection == original.collection && session.document.name == original.name
                    && SourceSelection.sameText(session.document.source, original.source)
                    && session.document.baseline == original.baseline && session.savedRevision == 0,
                    "The failed original save changed its identity, source or baseline")
        try require(session.recoveryRevision == model.sourceRevision
                    && session.recoveryDraft.map { SourceSelection.sameText($0.source, expected) && $0.baseline == original.baseline } == true,
                    "Recovery does not acknowledge the exact current native source revision")
    }

    func testWholeSourceNativeObjectSurvivesFailedSaveHeaderAndContinuedTypingWithoutRefocus() async throws {
        // This gate precedes creation of any fixture window. No process, device,
        // settings or application-window discovery outside this scene is needed.
        let foreground = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let scene = try XCTUnwrap(foreground.count == 1 ? foreground.first : nil,
                                 "Exactly one foreground synthetic test scene is required")
        let priorKey = scene.windows.first { $0.isKeyWindow }
        let storage = WorkspaceRetentionRecovery()
        let original = StoredDocument(collection: "Synthetic", name: "retention-fixture.mrk", source: "", baseline: Data())
        let recovery = DocumentRecovery(checkpoint: { await storage.checkpoint($0, source: $1) },
                                        complete: { await storage.complete($0) })
        let session = DocumentSession(document: original, recovery: recovery) { try await storage.save($0, source: $1) }
        let model = session.model
        model.showSource()
        let generation = model.editingGeneration
        var closeCalls = 0
        let workspace = DocumentWorkspace(session: session, collections: [original.collection],
            create: { try await storage.create($0, $1, $2) }, allowsSourceCopyExportPresentation: false,
            close: { closeCalls += 1 })
        let host = UIHostingController(rootView: workspace)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        var attachedSource: SourceTextView?
        defer {
            let stillOwnsKey = window.isKeyWindow
            if attachedSource?.window === window { attachedSource?.resignFirstResponder() }
            window.isHidden = true
            window.rootViewController = nil
            if stillOwnsKey && priorKey?.windowScene === scene { priorKey?.makeKey() }
        }
        window.makeKeyAndVisible()

        try await poll("The actual whole-source editor did not attach with its own automatic initial focus") {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            let sources = try self.sourceViews(in: host.view)
            guard sources.count == 1, let source = sources.first else { return false }
            attachedSource = source
            return source.window === window && source.isFirstResponder && source.bounds.width > 0 && source.bounds.height > 0
        }
        let source = try XCTUnwrap(attachedSource)
        // Capture identities without keeping the coordinator or undo manager
        // alive on the test's behalf during the header transition.
        let coordinatorID = ObjectIdentifier(try XCTUnwrap(source.delegate as? NativeSourceEditor.Coordinator,
                                                          "The real editor coordinator must be installed"))
        let undoID = ObjectIdentifier(try XCTUnwrap(source.undoManager, "Native input must provide its undo manager"))
        let initialOuter = try outerScrollView(of: source, window: window)
        let initialViewport = initialOuter.convert(initialOuter.bounds, to: host.view)
        try require(source.selectedRange == SourceSelection.beginning && model.documentSelection == SourceSelection.beginning,
                    "The empty synthetic source did not mount at its original caret")

        // No tap, explicit becomeFirstResponder or manual model/coordinator
        // report is allowed after mounting. Native insertion must report itself.
        source.insertText("Re")
        try await poll("Prefix insertion did not report exact bytes/caret through the real native coordinator") {
            SourceSelection.sameText(source.text, "Re") && SourceSelection.sameText(model.source, "Re")
                && source.selectedRange == NSRange(location: 2, length: 0)
                && model.documentSelection == NSRange(location: 2, length: 0) && source.undoManager?.canUndo == true
        }
        let firstFlush = await session.flush()
        try require(!firstFlush, "The fake conflict unexpectedly saved the original")
        var header = HeaderObservation()
        do {
            // SwiftUI may schedule onEdit after this explicit flush. Observe a
            // settled header beyond the 300 ms debounce without suspending it.
            try await poll("The actual attached failed-save/recovery header was not observable through public accessibility containers",
                           settledFor: .milliseconds(650)) {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                header = try self.headerObservation(in: host.view, window: window)
                return header.isPresent && !session.isSaving && session.canKeepRecovery
                    && session.recoveryRevision == model.sourceRevision
            }
        } catch {
            let currentOuter = try? outerScrollView(of: source, window: window)
            let diagnostic = XCTAttachment(string: "UNVERIFIED header observation: \(header)\nsource attached: \(source.window === window)\nsource first responder: \(source.isFirstResponder)\ninitial outer viewport: \(initialViewport)\ncurrent outer viewport: \(String(describing: currentOuter.map { $0.convert($0.bounds, to: host.view) }))")
            diagnostic.name = "Hosted UIKit recovery-header observation gate"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            throw error
        }
        try requireRetained(source, host: host.view, window: window, coordinatorID: coordinatorID, undoID: undoID,
                            session: session, model: model, generation: generation, expected: "Re", original: original)
        let firstCheckpoint = try XCTUnwrap(session.recoveryDraft)

        let suffix = "covery -- \"notes\" and café\n"
        let expected = "Recovery -- \"notes\" and café\n"
        source.insertText(suffix)
        try await poll("Continued native input lost exact source/caret without refocusing") {
            SourceSelection.sameText(source.text, expected) && SourceSelection.sameText(model.source, expected)
                && source.selectedRange == NSRange(location: expected.utf16.count, length: 0)
                && model.documentSelection == NSRange(location: expected.utf16.count, length: 0)
        }
        let secondFlush = await session.flush()
        try require(!secondFlush, "The second fake conflict unexpectedly saved the original")
        try await poll("The actual current recovery header was not attached after continued input", settledFor: .milliseconds(650)) {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            header = try self.headerObservation(in: host.view, window: window)
            return header.isPresent && !session.isSaving && session.canKeepRecovery
                && session.recoveryRevision == model.sourceRevision
        }
        try requireRetained(source, host: host.view, window: window, coordinatorID: coordinatorID, undoID: undoID,
                            session: session, model: model, generation: generation, expected: expected, original: original)
        try require(session.recoveryDraft?.id != firstCheckpoint.id, "Continued input retained only the prefix checkpoint token")
        let recorded = await storage.observation()
        try require(recorded.checkpoints.count >= 2 && recorded.savedSources.count >= 2,
                    "Both real session save attempts must reach the in-memory recovery/conflict hooks")
        try require(recorded.checkpoints.last.map { SourceSelection.sameText($0.source, expected) } == true
                    && recorded.savedSources.last.map { SourceSelection.sameText($0, expected) } == true,
                    "The in-memory hooks did not receive the complete current native source")
        try require(recorded.completedCount == 0 && recorded.createCount == 0 && closeCalls == 0,
                    "The fixture unexpectedly retired recovery, changed destination or closed the workspace")
        let finalOuter = try outerScrollView(of: source, window: window)
        let diagnostic = XCTAttachment(string: "Authored native insertion only; OS input/IME/undo acceptance remains open.\nheader: \(header)\ninitial outer viewport: \(initialViewport)\nsettled outer viewport: \(finalOuter.convert(finalOuter.bounds, to: host.view))\nsource object retained: true\nsource first responder: \(source.isFirstResponder)\nnative undo continuity: \(source.undoManager?.canUndo == true)")
        diagnostic.name = "Hosted UIKit source-retention observation"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }
}
