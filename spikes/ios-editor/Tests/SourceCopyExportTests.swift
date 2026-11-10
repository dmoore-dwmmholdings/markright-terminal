import Foundation
import XCTest
@testable import MarkrightEditorSpike

private actor ExportSessionHarness {
    private var events: [String] = []
    private var saveWaiter: CheckedContinuation<Void, Never>?
    private var createWaiter: CheckedContinuation<Void, Never>?
    private var pauseSave = false
    private var pauseCreate = false
    private var failSave = false
    func configure(pauseSave: Bool = false, pauseCreate: Bool = false, failSave: Bool = false) {
        self.pauseSave = pauseSave
        self.pauseCreate = pauseCreate
        self.failSave = failSave
    }
    func recorded() -> [String] { events }
    func releaseSave() { pauseSave = false; saveWaiter?.resume(); saveWaiter = nil }
    func releaseCreate() { pauseCreate = false; createWaiter?.resume(); createWaiter = nil }
    func save(_ document: StoredDocument, source: String) async throws -> StoredDocument {
        events.append("save")
        if pauseSave { await withCheckedContinuation { saveWaiter = $0 } }
        if failSave { throw CollectionStoreError.conflict }
        return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8))
    }
    func checkpoint(_ document: StoredDocument, source: String) -> RecoveryDraft {
        events.append("checkpoint")
        return RecoveryDraft(sessionID: UUID(), collection: document.collection, name: document.name,
                             source: source, baseline: document.baseline)
    }
    func complete(_ draft: RecoveryDraft) { events.append("complete") }
    func create(_ collection: String, _ name: String, _ source: String) async -> StoredDocument {
        events.append("create")
        if pauseCreate { await withCheckedContinuation { createWaiter = $0 } }
        return StoredDocument(collection: collection, name: name, source: source, baseline: Data(source.utf8))
    }
}

@MainActor final class SourceCopyExportTests: XCTestCase {
    private func make(source: String = "original", name: String = "Note.mrk", harness: ExportSessionHarness? = nil,
                      recovery: Bool = false) -> DocumentSession {
        let hooks = recovery ? harness.map { harness in
            DocumentRecovery(checkpoint: { await harness.checkpoint($0, source: $1) }, complete: { await harness.complete($0) })
        } : nil
        return DocumentSession(document: StoredDocument(collection: "Notes", name: name, source: source, baseline: Data(source.utf8)),
                               recovery: hooks) { document, source in
            if let harness { return try await harness.save(document, source: source) }
            return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8))
        }
    }

    private func edit(_ session: DocumentSession, _ source: String, composing: Bool = false,
                      selection: NSRange? = nil) {
        if !session.model.sourceMode { session.model.showSource() }
        session.model.updateDocumentSource(source, composing: composing,
                                           generation: session.model.editingGeneration, selection: selection)
    }

    private func waitFor(_ event: String, harness: ExportSessionHarness) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await harness.recorded().contains(event)) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        let events = await harness.recorded()
        XCTAssertTrue(events.contains(event), "Session did not reach \(event)")
    }

    func testSnapshotsExactBytesInBlockSourceAndReadingModesIncludingEmptySource() throws {
        for source in ["", "\u{FEFF}Cafe\u{301} 😀\r\nnext\rlast\n"] {
            let session = make(source: source, name: "Cafe\u{301}.MD")
            let block = try SourceCopySnapshot(session: session)
            XCTAssertEqual(block.data, Data(source.utf8))
            XCTAssertEqual(block.format, .markdown)
            XCTAssertTrue(block.suggestedFilename.utf8.elementsEqual("Cafe\u{301}.MD".utf8))
            XCTAssertEqual(block.sessionID, session.id)
            session.model.showSource()
            let whole = try SourceCopySnapshot(session: session)
            XCTAssertEqual(whole.data, block.data)
            session.model.setReadingMode(true)
            let reading = try SourceCopySnapshot(session: session)
            XCTAssertEqual(reading.data, block.data)
            XCTAssertTrue(session.model.readingMode)
            XCTAssertNotEqual(block.id, whole.id)
        }
        XCTAssertEqual(try SourceCopySnapshot(session: make(name: "Note.MrK")).format, .markright)
    }

    func testFilenameValidationRejectsPathsControlCharactersAndUnsupportedSuffixes() {
        for name in ["", ".md", "../Note.md", "folder/Note.mrk", "folder\\Note.md", "Note\n.md", "Note\u{0}.mrk", "Note", "Note.txt", "Note.md ", String(repeating: "x", count: 253) + ".md"] {
            XCTAssertThrowsError(try SourceCopySnapshot(session: make(name: name))) {
                XCTAssertEqual($0 as? SourceCopyExportError, .invalidFilename, name)
            }
        }
    }

    func testUTF8ByteLimitAcceptsBoundaryAndRejectsFirstExcessByte() throws {
        let session = make(source: "")
        let maximum = String(repeating: "😀", count: SourceCopySnapshot.maximumBytes / 4)
        edit(session, maximum)
        XCTAssertEqual(try SourceCopySnapshot(session: session).data.count, SourceCopySnapshot.maximumBytes)
        edit(session, maximum + "x")
        XCTAssertThrowsError(try SourceCopySnapshot(session: session)) {
            XCTAssertEqual($0 as? SourceCopyExportError, .tooLarge)
        }
        XCTAssertTrue(session.model.source.utf8.elementsEqual((maximum + "x").utf8))

        // Exercise the cumulative bound across a block, its original separator,
        // and the following block without first joining their full source.
        let blocks = make(source: "\n")
        blocks.model.update(0, String(repeating: "x", count: SourceCopySnapshot.maximumBytes - 1))
        XCTAssertEqual(try SourceCopySnapshot(session: blocks).data.count, SourceCopySnapshot.maximumBytes)
        blocks.model.update(1, "x")
        XCTAssertThrowsError(try SourceCopySnapshot(session: blocks)) {
            XCTAssertEqual($0 as? SourceCopyExportError, .tooLarge)
        }
    }

    func testCompositionIsRefusedWithoutChangingVisibleSourceOrEditorState() {
        let session = make()
        edit(session, "に", composing: true)
        let generation = session.model.editingGeneration
        let revision = session.model.sourceRevision
        let export = SourceCopyExportModel()
        XCTAssertFalse(export.begin(session: session))
        XCTAssertNotNil(export.message)
        XCTAssertFalse(export.isPending)
        XCTAssertTrue(session.model.composing)
        XCTAssertEqual(session.model.source, "に")
        XCTAssertEqual(session.model.editingGeneration, generation)
        XCTAssertEqual(session.model.sourceRevision, revision)
    }

    func testExportSuccessLeavesConflictedDirtyRecoveryBaselineCaretAndGenerationUnchanged() async throws {
        let harness = ExportSessionHarness()
        await harness.configure(failSave: true)
        let session = make(harness: harness, recovery: true)
        let source = "\u{FEFF}unsaved Cafe\u{301}\r\n"
        let selection = NSRange(location: 2, length: 3)
        edit(session, source, selection: selection)
        let saved = await session.flush()
        XCTAssertFalse(saved)
        let baseline = session.document.baseline
        let checkpoint = try XCTUnwrap(session.recoveryDraft)
        let recoveryRevision = session.recoveryRevision
        let generation = session.model.editingGeneration
        let revision = session.model.sourceRevision
        let error = session.errorMessage
        let events = await harness.recorded()
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: session))
        let snapshot = try XCTUnwrap(export.request)
        XCTAssertEqual(snapshot.data, Data(source.utf8))
        XCTAssertEqual(snapshot.sourceRevision, revision)
        XCTAssertTrue(export.finish(id: snapshot.id, result: .success(())))
        XCTAssertTrue(export.message?.contains("still editing the original") == true)
        XCTAssertTrue(session.dirty)
        XCTAssertFalse(session.canClose)
        XCTAssertEqual(session.document.collection, "Notes")
        XCTAssertEqual(session.document.name, "Note.mrk")
        XCTAssertEqual(session.document.baseline, baseline)
        XCTAssertEqual(session.savedRevision, 0)
        XCTAssertEqual(session.recoveryDraft?.id, checkpoint.id)
        XCTAssertEqual(session.recoveryRevision, recoveryRevision)
        XCTAssertTrue(session.canKeepRecovery)
        XCTAssertEqual(session.errorMessage, error)
        XCTAssertEqual(session.model.documentSelection, selection)
        XCTAssertEqual(session.model.editingGeneration, generation)
        XCTAssertEqual(session.model.sourceRevision, revision)
        XCTAssertEqual(Data(session.model.source.utf8), snapshot.data)
        let after = await harness.recorded()
        XCTAssertEqual(after, events)
    }

    func testInFlightSaveAllowsSnapshotWithoutSuspendingOrCompletingOriginalSave() async throws {
        let harness = ExportSessionHarness()
        await harness.configure(pauseSave: true)
        let session = make(harness: harness)
        edit(session, "first")
        let flush = Task { await session.flush() }
        await waitFor("save", harness: harness)
        XCTAssertTrue(session.isSaving)
        edit(session, "newest unsaved")
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: session))
        let snapshot = try XCTUnwrap(export.request)
        XCTAssertEqual(snapshot.data, Data("newest unsaved".utf8))
        XCTAssertTrue(export.finish(id: snapshot.id, result: .success(())))
        XCTAssertTrue(session.isSaving)
        XCTAssertTrue(session.dirty)
        XCTAssertEqual(session.document.baseline, Data("original".utf8))
        await harness.releaseSave()
        let saved = await flush.value
        XCTAssertTrue(saved)
        XCTAssertEqual(session.document.source, "newest unsaved")
        XCTAssertEqual(snapshot.data, Data("newest unsaved".utf8))
    }

    func testDestinationChangeRefusesSnapshotWithoutInterferingWithCopy() async {
        let harness = ExportSessionHarness()
        await harness.configure(pauseCreate: true)
        let session = make(harness: harness)
        edit(session, "copied")
        let destination = Task {
            await session.saveAs(collection: "Copies", name: "Copy.md") { await harness.create($0, $1, $2) }
        }
        await waitFor("create", harness: harness)
        XCTAssertTrue(session.isChangingDestination)
        let export = SourceCopyExportModel()
        XCTAssertFalse(export.begin(session: session))
        XCTAssertNotNil(export.message)
        XCTAssertNil(export.request)
        XCTAssertTrue(session.isChangingDestination)
        XCTAssertEqual(session.document.name, "Note.mrk")
        await harness.releaseCreate()
        let receipt = await destination.value
        XCTAssertEqual(receipt?.name, "Copy.md")
    }

    func testPendingExportDoesNotCancelScheduledAutosave() async throws {
        let harness = ExportSessionHarness()
        let session = make(harness: harness)
        edit(session, "scheduled source")
        session.scheduleSave()
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: session))
        let snapshot = try XCTUnwrap(export.request)
        await waitFor("save", harness: harness)
        let saved = await session.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(session.document.source, "scheduled source")
        XCTAssertEqual(export.request?.id, snapshot.id)
        XCTAssertEqual(snapshot.data, Data("scheduled source".utf8))
        XCTAssertTrue(export.cancel(id: snapshot.id))
    }

    func testPendingSnapshotIsImmutableAndSecondBeginDoesNotReplaceIt() throws {
        let session = make()
        edit(session, "captured")
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: session))
        let first = try XCTUnwrap(export.request)
        edit(session, "later")
        XCTAssertNotEqual(session.model.sourceRevision, first.sourceRevision)
        XCTAssertFalse(export.begin(session: session))
        XCTAssertEqual(export.request?.id, first.id)
        XCTAssertEqual(export.request?.data, Data("captured".utf8))
        XCTAssertNil(export.message)
        XCTAssertTrue(export.finish(id: first.id, result: .success(())))
        XCTAssertTrue(session.dirty)
        XCTAssertFalse(session.canClose)
        XCTAssertEqual(session.model.source, "later")
        XCTAssertEqual(first.data, Data("captured".utf8))
    }

    func testStaleDuplicateFailureAndCancelCallbacksCannotAffectNewRequest() throws {
        let session = make()
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: session))
        let first = try XCTUnwrap(export.request)
        XCTAssertFalse(export.finish(id: UUID(), result: .success(())))
        XCTAssertFalse(export.cancel(id: UUID()))
        XCTAssertEqual(export.request?.id, first.id)
        XCTAssertNil(export.message)
        XCTAssertTrue(export.finish(id: first.id, result: .failure(CocoaError(.fileWriteUnknown))))
        let failure = export.message
        XCTAssertTrue(failure?.contains("not confirmed") == true)
        XCTAssertTrue(failure?.contains("Check the destination before retrying") == true)
        XCTAssertFalse(export.isPending)
        XCTAssertFalse(export.finish(id: first.id, result: .success(())))
        XCTAssertEqual(export.message, failure)
        XCTAssertTrue(export.begin(session: session))
        let retry = try XCTUnwrap(export.request)
        XCTAssertNotEqual(first.id, retry.id)
        XCTAssertNil(export.message)
        XCTAssertFalse(export.cancel(id: first.id))
        XCTAssertFalse(export.finish(id: first.id, result: .failure(CancellationError())))
        XCTAssertEqual(export.request?.id, retry.id)
        XCTAssertNil(export.message)
        XCTAssertTrue(export.cancel(id: retry.id))
        let cancelled = export.message
        XCTAssertTrue(cancelled?.contains("cancelled") == true)
        XCTAssertFalse(export.cancel(id: retry.id))
        XCTAssertEqual(export.message, cancelled)
    }

    func testCancellationErrorsAreClassifiedAndLaterBeginClearsMessage() throws {
        let session = make()
        let export = SourceCopyExportModel()
        let errors: [any Error] = [CancellationError(), CocoaError(.userCancelled)]
        for error in errors {
            XCTAssertTrue(export.begin(session: session))
            XCTAssertNil(export.message)
            let snapshot = try XCTUnwrap(export.request)
            XCTAssertTrue(export.finish(id: snapshot.id, result: .failure(error)))
            XCTAssertTrue(export.message?.contains("cancelled") == true)
            XCTAssertFalse(export.isPending)
        }
    }

    func testPendingSnapshotDoesNotRetainSession() throws {
        var session: DocumentSession? = make()
        weak var observed = session
        let export = SourceCopyExportModel()
        XCTAssertTrue(export.begin(session: try XCTUnwrap(session)))
        let snapshot = try XCTUnwrap(export.request)
        session = nil
        XCTAssertNil(observed)
        observed = nil
        XCTAssertEqual(snapshot.data, Data("original".utf8))
        XCTAssertTrue(export.finish(id: snapshot.id, result: .success(())))
    }
}
