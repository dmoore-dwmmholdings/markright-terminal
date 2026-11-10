import XCTest
@testable import MarkrightEditorSpike

private actor SaveAsHarness {
    enum Stage: String, Sendable { case checkpoint, save, create, complete }
    struct Call: Sendable {
        let stage: Stage
        let collection: String
        let name: String
        let source: String
        let baseline: Data
    }
    private var calls: [Call] = []
    private var paused: Set<Stage> = []
    private var waiters: [Stage: CheckedContinuation<Void, Never>] = [:]
    private var failures: [Stage: CollectionStoreError] = [:]
    private var createWarning: String?
    private let sessionID = UUID()

    func pause(_ stage: Stage) { paused.insert(stage) }
    func release(_ stage: Stage) {
        paused.remove(stage)
        waiters.removeValue(forKey: stage)?.resume()
    }
    func fail(_ stage: Stage, with error: CollectionStoreError?) { failures[stage] = error }
    func warnOnCreate(_ warning: String) { createWarning = warning }
    func recorded(_ stage: Stage? = nil) -> [Call] {
        calls.filter { stage == nil || $0.stage == stage }
    }
    private func proceed(_ stage: Stage) async throws {
        if paused.contains(stage) {
            await withCheckedContinuation { waiters[stage] = $0 }
        }
        if let error = failures[stage] { throw error }
    }
    func checkpoint(_ document: StoredDocument, source: String) async throws -> RecoveryDraft {
        calls.append(Call(stage: .checkpoint, collection: document.collection, name: document.name,
                          source: source, baseline: document.baseline))
        try await proceed(.checkpoint)
        return RecoveryDraft(sessionID: sessionID, collection: document.collection, name: document.name,
                             source: source, baseline: document.baseline)
    }
    func complete(_ draft: RecoveryDraft) async throws {
        calls.append(Call(stage: .complete, collection: draft.collection, name: draft.name,
                          source: draft.source, baseline: draft.baseline))
        try await proceed(.complete)
    }
    func save(_ document: StoredDocument, source: String) async throws -> StoredDocument {
        calls.append(Call(stage: .save, collection: document.collection, name: document.name,
                          source: source, baseline: document.baseline))
        try await proceed(.save)
        return StoredDocument(collection: document.collection, name: document.name,
                              source: source, baseline: Data(source.utf8))
    }
    func create(collection: String, name: String, source: String) async throws -> StoredDocument {
        calls.append(Call(stage: .create, collection: collection, name: name,
                          source: source, baseline: Data()))
        try await proceed(.create)
        return StoredDocument(collection: collection, name: name, source: source,
                              baseline: Data(source.utf8), durabilityWarning: createWarning)
    }
}

@MainActor final class SaveAsSessionTests: XCTestCase {
    private func make(_ harness: SaveAsHarness, recoveryEnabled: Bool = true) -> DocumentSession {
        let recovery = recoveryEnabled ? DocumentRecovery(
            checkpoint: { try await harness.checkpoint($0, source: $1) },
            complete: { try await harness.complete($0) }) : nil
        return DocumentSession(document: StoredDocument(collection: "Notes", name: "original.mrk",
                                                        source: "original", baseline: Data("original".utf8)),
                               recovery: recovery) { try await harness.save($0, source: $1) }
    }
    private func edit(_ session: DocumentSession, _ source: String, composing: Bool = false,
                      selection: NSRange? = nil) {
        if !session.model.sourceMode { session.model.showSource() }
        session.model.updateDocumentSource(source, composing: composing,
                                           generation: session.model.editingGeneration, selection: selection)
    }
    private func copy(_ session: DocumentSession, harness: SaveAsHarness,
                      name: String = "copy.mrk") async -> StoredDocument? {
        await session.saveAs(collection: "Copies", name: name) {
            try await harness.create(collection: $0, name: $1, source: $2)
        }
    }
    private func waitFor(_ stage: SaveAsHarness.Stage, count: Int = 1, harness: SaveAsHarness) async {
        for _ in 0..<1000 {
            if await harness.recorded(stage).count >= count { return }
            await Task.yield()
        }
        XCTFail("Save As pipeline did not reach \(stage)")
    }
    private func waitForDestinationChange(_ session: DocumentSession) async {
        for _ in 0..<1000 {
            if session.isChangingDestination { return }
            await Task.yield()
        }
        XCTFail("Save As did not acquire the destination change")
    }

    func testCopyPreservesExactUTF8AndEditorIdentityCaretAndGeneration() async {
        let harness = SaveAsHarness()
        let session = make(harness)
        let source = "\u{FEFF}Cafe\u{301} 😀\r\nnext\rlast\n"
        let selection = NSRange(location: 2, length: 3)
        edit(session, source, selection: selection)
        let model = session.model
        let generation = model.editingGeneration
        let revision = model.sourceRevision
        let receipt = await copy(session, harness: harness)

        XCTAssertNotNil(receipt)
        XCTAssertTrue(session.model === model)
        XCTAssertEqual(model.documentSelection, selection)
        XCTAssertEqual(model.editingGeneration, generation)
        XCTAssertEqual(model.sourceRevision, revision)
        XCTAssertEqual(Array(model.source.utf8), Array(source.utf8))
        XCTAssertEqual(session.document.baseline, Data(source.utf8))
        XCTAssertEqual(session.document.collection, "Copies")
        XCTAssertEqual(session.document.name, "copy.mrk")
        XCTAssertEqual(session.savedRevision, revision)
        XCTAssertTrue(session.canClose)
        XCTAssertNil(session.recoveryDraft)
        let calls = await harness.recorded()
        XCTAssertEqual(calls.map(\.stage), [.checkpoint, .create, .complete])
        XCTAssertEqual(calls[0].baseline, Data("original".utf8))
        XCTAssertEqual(Array(calls[0].source.utf8), Array(source.utf8))
        XCTAssertEqual(Array(calls[1].source.utf8), Array(source.utf8))
    }

    func testActiveAutosaveReceiptFinishesWithoutAnotherOldDestinationWrite() async {
        let harness = SaveAsHarness()
        await harness.pause(.save)
        await harness.pause(.create)
        let session = make(harness)
        edit(session, "first")
        let originalFlush = Task { await session.flush() }
        await waitFor(.save, harness: harness)
        edit(session, "newest")
        let copying = Task { await self.copy(session, harness: harness) }
        await waitForDestinationChange(session)
        session.scheduleSave()
        XCTAssertEqual(session.status, "Saving new document…")
        XCTAssertFalse(session.canClose)
        XCTAssertFalse(session.canKeepRecovery)
        XCTAssertFalse(session.prepareRecoveryClose())
        let beforeRelease = await harness.recorded(.create)
        XCTAssertTrue(beforeRelease.isEmpty)
        await harness.release(.save)
        await waitFor(.create, harness: harness)
        _ = await originalFlush.value
        XCTAssertEqual(session.document.name, "original.mrk")
        XCTAssertEqual(session.document.baseline, Data("first".utf8))
        let checkpoints = await harness.recorded(.checkpoint)
        XCTAssertEqual(checkpoints.map(\.source), ["first", "newest"])
        XCTAssertEqual(checkpoints.last?.baseline, Data("first".utf8))
        await harness.release(.create)
        let receipt = await copying.value
        XCTAssertEqual(receipt?.source, "newest")
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves[0].name, "original.mrk")
        XCTAssertFalse(session.dirty)
    }

    func testEditsDuringCreateStayDirtyAndFlushUsesNewReceiptBaseline() async {
        let harness = SaveAsHarness()
        await harness.pause(.create)
        let session = make(harness)
        edit(session, "snapshot")
        let snapshotRevision = session.model.sourceRevision
        let copying = Task { await self.copy(session, harness: harness) }
        await waitFor(.create, harness: harness)
        edit(session, "newest 😀\r\n")
        session.scheduleSave()
        await harness.release(.create)
        let receipt = await copying.value
        XCTAssertEqual(receipt?.source, "snapshot")
        XCTAssertEqual(session.savedRevision, snapshotRevision)
        XCTAssertTrue(session.dirty)
        XCTAssertFalse(session.isChangingDestination)
        let result = await session.flush()
        XCTAssertTrue(result)
        XCTAssertEqual(session.document.source, "newest 😀\r\n")
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves[0].collection, "Copies")
        XCTAssertEqual(saves[0].name, "copy.mrk")
        XCTAssertEqual(saves[0].baseline, Data("snapshot".utf8))
    }

    func testConcurrentCopyIsRefusedAndFlushJoinsCopyThenNewestEdits() async {
        let harness = SaveAsHarness()
        await harness.pause(.create)
        let session = make(harness)
        edit(session, "snapshot")
        let copying = Task { await self.copy(session, harness: harness) }
        await waitFor(.create, harness: harness)
        let duplicate = await copy(session, harness: harness, name: "duplicate.mrk")
        XCTAssertNil(duplicate)
        XCTAssertTrue(session.isChangingDestination)
        edit(session, "newest")
        let flushing = Task { await session.flush() }
        await Task.yield()
        let savesBeforeReceipt = await harness.recorded(.save)
        XCTAssertTrue(savesBeforeReceipt.isEmpty)
        await harness.release(.create)
        let receipt = await copying.value
        let flushed = await flushing.value
        XCTAssertNotNil(receipt)
        XCTAssertTrue(flushed)
        XCTAssertFalse(session.isChangingDestination)
        XCTAssertEqual(session.document.name, "copy.mrk")
        XCTAssertEqual(session.document.source, "newest")
        let creates = await harness.recorded(.create)
        XCTAssertEqual(creates.count, 1)
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.map(\.name), ["copy.mrk"])
        XCTAssertEqual(saves.map(\.baseline), [Data("snapshot".utf8)])
    }

    func testEditsDuringCopyAutomaticallySaveToNewDestinationAfterReceipt() async throws {
        let harness = SaveAsHarness()
        await harness.pause(.create)
        let session = make(harness)
        edit(session, "snapshot")
        let copying = Task { await self.copy(session, harness: harness) }
        await waitFor(.create, harness: harness)
        edit(session, "newest")
        session.scheduleSave()
        await harness.release(.create)
        _ = await copying.value
        // The copy must release its task before the normal debounce starts a
        // pump. No explicit flush should be needed to preserve these edits.
        for _ in 0..<200 {
            if session.canClose { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(session.canClose)
        XCTAssertEqual(session.document.source, "newest")
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.map(\.name), ["copy.mrk"])
        XCTAssertEqual(saves.map(\.baseline), [Data("snapshot".utf8)])
    }

    func testCollisionAndCreateFailurePreserveOriginalAndCurrentRecoveryAcknowledgement() async {
        for error in [CollectionStoreError.collision("copy.mrk"), .io(operation: "publish document", code: 5)] {
            let harness = SaveAsHarness()
            await harness.fail(.create, with: error)
            let session = make(harness)
            edit(session, "unsaved\r\n")
            let receipt = await copy(session, harness: harness)
            XCTAssertNil(receipt)
            XCTAssertFalse(session.isChangingDestination)
            XCTAssertEqual(session.document.name, "original.mrk")
            XCTAssertEqual(session.document.baseline, Data("original".utf8))
            XCTAssertEqual(session.model.source, "unsaved\r\n")
            XCTAssertTrue(session.dirty)
            XCTAssertTrue(session.canKeepRecovery)
            XCTAssertEqual(session.recoveryRevision, session.model.sourceRevision)
            XCTAssertNotNil(session.destinationError)
            XCTAssertNil(session.errorMessage)
            let calls = await harness.recorded()
            XCTAssertEqual(calls.map(\.stage), [.checkpoint, .create])
        }
    }

    func testFailedCopyWithNewerEditsCannotAdvertiseSnapshotAsCurrentRecovery() async {
        let harness = SaveAsHarness()
        await harness.pause(.create)
        await harness.fail(.create, with: .collision("copy.mrk"))
        let session = make(harness)
        edit(session, "snapshot")
        let copying = Task { await self.copy(session, harness: harness) }
        await waitFor(.create, harness: harness)
        edit(session, "newest")
        await harness.release(.create)
        let receipt = await copying.value
        XCTAssertNil(receipt)
        XCTAssertEqual(session.document.name, "original.mrk")
        XCTAssertEqual(session.model.source, "newest")
        XCTAssertEqual(session.recoveryDraft?.source, "snapshot")
        XCTAssertFalse(session.canKeepRecovery)
        XCTAssertFalse(session.prepareRecoveryClose())
    }

    func testCheckpointFailureInvalidatesPreviousAcknowledgementAndDoesNotCreate() async {
        let harness = SaveAsHarness()
        await harness.fail(.save, with: .conflict)
        let session = make(harness)
        edit(session, "unsaved")
        _ = await session.flush()
        XCTAssertTrue(session.canKeepRecovery)
        let oldSaveError = session.errorMessage
        await harness.fail(.checkpoint, with: .io(operation: "checkpoint", code: 5))
        let receipt = await copy(session, harness: harness)
        XCTAssertNil(receipt)
        XCTAssertEqual(session.document.name, "original.mrk")
        XCTAssertEqual(session.document.baseline, Data("original".utf8))
        XCTAssertEqual(session.model.source, "unsaved")
        XCTAssertNil(session.recoveryRevision)
        XCTAssertFalse(session.canKeepRecovery)
        XCTAssertEqual(session.errorMessage, oldSaveError)
        XCTAssertNotNil(session.destinationError)
        let creates = await harness.recorded(.create)
        XCTAssertTrue(creates.isEmpty)
    }

    func testSuccessfulCopyAfterSaveConflictClearsOldSaveErrorAndKeepsOriginalBaselineForCheckpoint() async {
        let harness = SaveAsHarness()
        await harness.fail(.save, with: .conflict)
        let session = make(harness)
        edit(session, "unsaved")
        _ = await session.flush()
        XCTAssertNotNil(session.errorMessage)
        let receipt = await copy(session, harness: harness)
        XCTAssertNotNil(receipt)
        XCTAssertEqual(session.document.name, "copy.mrk")
        XCTAssertEqual(session.document.baseline, Data("unsaved".utf8))
        XCTAssertNil(session.errorMessage)
        XCTAssertNil(session.destinationError)
        XCTAssertTrue(session.canClose)
        let checkpoints = await harness.recorded(.checkpoint)
        XCTAssertEqual(checkpoints.map(\.baseline), [Data("original".utf8), Data("original".utf8)])
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.count, 1)
    }

    func testCompositionBeforeCopyDoesNotCheckpointOrCreate() async {
        let harness = SaveAsHarness()
        let session = make(harness)
        edit(session, "に", composing: true)
        let receipt = await copy(session, harness: harness)
        XCTAssertNil(receipt)
        XCTAssertFalse(session.isChangingDestination)
        XCTAssertNotNil(session.destinationError)
        XCTAssertEqual(session.model.source, "に")
        let calls = await harness.recorded()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCompositionStartedWhileWaitingForOldSaveRefusesCopyAfterReceipt() async {
        let harness = SaveAsHarness()
        await harness.pause(.save)
        let session = make(harness)
        edit(session, "first")
        let flushing = Task { await session.flush() }
        await waitFor(.save, harness: harness)
        let copying = Task { await self.copy(session, harness: harness) }
        await waitForDestinationChange(session)
        edit(session, "に", composing: true)
        await harness.release(.save)
        _ = await flushing.value
        let receipt = await copying.value
        XCTAssertNil(receipt)
        XCTAssertEqual(session.document.name, "original.mrk")
        XCTAssertEqual(session.document.baseline, Data("first".utf8))
        XCTAssertEqual(session.model.source, "に")
        XCTAssertTrue(session.dirty)
        XCTAssertFalse(session.isChangingDestination)
        XCTAssertNotNil(session.destinationError)
        let calls = await harness.recorded()
        XCTAssertEqual(calls.map(\.stage), [.checkpoint, .save, .complete])
    }

    func testCommittedDurabilityWarningAdoptsNewDocumentAndRetainsRecoveryUntilRetry() async {
        let harness = SaveAsHarness()
        await harness.warnOnCreate("New document committed; durability uncertain.")
        let session = make(harness)
        edit(session, "committed")
        let receipt = await copy(session, harness: harness)
        XCTAssertNotNil(receipt)
        XCTAssertEqual(session.document.name, "copy.mrk")
        XCTAssertEqual(session.document.baseline, Data("committed".utf8))
        XCTAssertNotNil(session.document.durabilityWarning)
        XCTAssertFalse(session.dirty)
        XCTAssertFalse(session.canClose)
        XCTAssertTrue(session.canKeepRecovery)
        XCTAssertNil(session.destinationError)
        let initialCalls = await harness.recorded()
        XCTAssertEqual(initialCalls.map(\.stage), [.checkpoint, .create])
        let retried = await session.flush()
        XCTAssertTrue(retried)
        XCTAssertNil(session.recoveryDraft)
        XCTAssertNil(session.document.durabilityWarning)
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.map(\.name), ["copy.mrk"])
        XCTAssertEqual(saves.map(\.baseline), [Data("committed".utf8)])
    }

    func testCleanupFailureRetainsCommittedReceiptAndPendingCleanupCanRetry() async {
        let harness = SaveAsHarness()
        await harness.fail(.complete, with: .io(operation: "retire checkpoint", code: 5))
        let session = make(harness)
        edit(session, "committed")
        let receipt = await copy(session, harness: harness)
        XCTAssertNotNil(receipt)
        XCTAssertEqual(session.document.name, "copy.mrk")
        XCTAssertEqual(session.document.baseline, Data("committed".utf8))
        XCTAssertFalse(session.dirty)
        XCTAssertTrue(session.canClose)
        XCTAssertTrue(session.recoveryCleanupPending)
        XCTAssertFalse(session.canKeepRecovery)
        XCTAssertNil(session.recoveryRevision)
        XCTAssertTrue(session.destinationError?.hasPrefix("New document saved.") == true)
        XCTAssertEqual(session.errorMessage, session.destinationError)
        await harness.fail(.complete, with: nil)
        let retried = await session.flush()
        XCTAssertTrue(retried)
        XCTAssertFalse(session.recoveryCleanupPending)
        XCTAssertNil(session.recoveryDraft)
        XCTAssertNil(session.errorMessage)
        let saves = await harness.recorded(.save)
        XCTAssertEqual(saves.map(\.name), ["copy.mrk"])
        XCTAssertEqual(saves.map(\.baseline), [Data("committed".utf8)])
    }

    func testCopyWithoutRecoveryStillAdoptsReceiptAndPreservesEditor() async {
        let harness = SaveAsHarness()
        let session = make(harness, recoveryEnabled: false)
        edit(session, "new")
        let model = session.model
        let receipt = await copy(session, harness: harness)
        XCTAssertNotNil(receipt)
        XCTAssertTrue(session.model === model)
        XCTAssertTrue(session.canClose)
        let calls = await harness.recorded()
        XCTAssertEqual(calls.map(\.stage), [.create])
    }

    func testDismissedFailedCopyResumesOriginalAutosaveWithoutAnotherEditOrFlush() async throws {
        for newerDuringCreate in [false, true] {
            let harness = SaveAsHarness()
            await harness.fail(.create, with: .collision("copy.mrk"))
            if newerDuringCreate { await harness.pause(.create) }
            let session = make(harness)
            edit(session, "pending")
            session.scheduleSave()
            let copying = Task { await self.copy(session, harness: harness) }
            if newerDuringCreate {
                await waitFor(.create, harness: harness)
                edit(session, "newest")
                session.scheduleSave()
                await harness.release(.create)
            }
            let receipt = await copying.value
            XCTAssertNil(receipt); XCTAssertTrue(session.dirty)
            session.resumeAfterSaveAsDialog()
            for _ in 0..<200 {
                if session.canClose { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertTrue(session.canClose)
            XCTAssertEqual(session.document.name, "original.mrk")
            XCTAssertEqual(session.document.source, newerDuringCreate ? "newest" : "pending")
            let saves = await harness.recorded(.save)
            XCTAssertEqual(saves.map(\.name), ["original.mrk"])
            XCTAssertEqual(saves.map(\.source), [newerDuringCreate ? "newest" : "pending"])
        }
    }
    func testPreparingSaveAsDialogClearsOnlyDestinationError() async {
        let harness = SaveAsHarness()
        await harness.fail(.save, with: .conflict)
        await harness.fail(.create, with: .collision("copy.mrk"))
        let session = make(harness)
        edit(session, "unsaved")
        _ = await session.flush()
        let saveError = session.errorMessage
        _ = await copy(session, harness: harness)
        XCTAssertNotNil(session.destinationError)
        session.prepareSaveAsDialog()
        XCTAssertNil(session.destinationError)
        XCTAssertEqual(session.errorMessage, saveError)
        XCTAssertEqual(session.document.name, "original.mrk")
        XCTAssertEqual(session.model.source, "unsaved")
    }
}
