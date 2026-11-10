import XCTest
@testable import MarkrightEditorSpike

private actor RecoveryHarness {
    var events: [String] = []
    var checkpointFails = false
    var saveFails = false
    var cleanupFails = false
    var warnOnce = false
    var pauseSave = false
    var pauseCheckpoint = false
    var pauseComplete = false
    private var checkpointWaiter: CheckedContinuation<Void, Never>?
    private var completionWaiter: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    let sessionID = UUID()
    func configure(checkpointFails: Bool = false, saveFails: Bool = false, cleanupFails: Bool = false, warnOnce: Bool = false, pauseSave: Bool = false, pauseCheckpoint: Bool = false, pauseComplete: Bool = false) {
        self.checkpointFails = checkpointFails; self.saveFails = saveFails
        self.cleanupFails = cleanupFails; self.warnOnce = warnOnce; self.pauseSave = pauseSave
        self.pauseCheckpoint = pauseCheckpoint; self.pauseComplete = pauseComplete
    }
    func recorded() -> [String] { events }
    func release() { pauseSave = false; waiter?.resume(); waiter = nil }
    func releaseCheckpoint() { pauseCheckpoint = false; checkpointWaiter?.resume(); checkpointWaiter = nil }
    func releaseComplete() { pauseComplete = false; completionWaiter?.resume(); completionWaiter = nil }
    func checkpoint(_ document: StoredDocument, source: String) async throws -> RecoveryDraft {
        events.append("checkpoint")
        if pauseCheckpoint { await withCheckedContinuation { checkpointWaiter = $0 } }
        if checkpointFails { throw CocoaError(.fileWriteNoPermission) }
        return RecoveryDraft(sessionID: sessionID, collection: document.collection, name: document.name, source: source, baseline: document.baseline)
    }
    func save(_ document: StoredDocument, source: String) async throws -> StoredDocument {
        events.append("save")
        if pauseSave { await withCheckedContinuation { waiter = $0 } }
        if saveFails { throw CollectionStoreError.conflict }
        let warning = warnOnce ? "Durability uncertain" : nil
        warnOnce = false
        return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8), durabilityWarning: warning)
    }
    func complete(_ draft: RecoveryDraft) async throws {
        events.append("complete")
        if pauseComplete { await withCheckedContinuation { completionWaiter = $0 } }
        if cleanupFails { throw CocoaError(.fileWriteNoPermission) }
    }
}

@MainActor final class RecoverySessionTests: XCTestCase {
    private func make(_ harness: RecoveryHarness) -> DocumentSession {
        let recovery = DocumentRecovery(checkpoint: { try await harness.checkpoint($0, source: $1) }, complete: { try await harness.complete($0) })
        return DocumentSession(document: StoredDocument(collection: "Notes", name: "note.mrk", source: "old", baseline: Data("old".utf8)), recovery: recovery) {
            try await harness.save($0, source: $1)
        }
    }
    private func edit(_ session: DocumentSession, _ source: String, composing: Bool = false) {
        if !session.model.sourceMode { session.model.showSource() }
        session.model.updateDocumentSource(source, composing: composing, generation: session.model.editingGeneration)
    }
    func testFailedDocumentSaveRetainsAcknowledgedExactRecoveryAndAllowsExplicitClose() async {
        let harness = RecoveryHarness(); await harness.configure(saveFails: true)
        let session = make(harness)
        let source = "\u{FEFF}new 😀\r\nCafe\u{301}\r"
        edit(session, source)
        let saved = await session.flush()
        XCTAssertFalse(saved); XCTAssertFalse(session.canClose)
        XCTAssertTrue(session.canKeepRecovery); XCTAssertTrue(session.prepareRecoveryClose())
        XCTAssertEqual(Array(session.recoveryDraft!.source.utf8), Array(source.utf8))
        XCTAssertEqual(session.document.baseline, Data("old".utf8))
        let events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save"])
    }
    func testCheckpointFailureBlocksDocumentWriteAndInvalidatesOldAcknowledgement() async {
        let harness = RecoveryHarness(); await harness.configure(saveFails: true)
        let session = make(harness); edit(session, "new")
        _ = await session.flush()
        XCTAssertTrue(session.canKeepRecovery)
        await harness.configure(checkpointFails: true)
        _ = await session.flush()
        XCTAssertFalse(session.canKeepRecovery); XCTAssertFalse(session.prepareRecoveryClose())
        XCTAssertEqual(session.model.source, "new")
        let events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "checkpoint"])
    }
    func testNewerEditsDuringFailedSaveCannotUseOlderRecoveryAcknowledgement() async throws {
        let harness = RecoveryHarness(); await harness.configure(saveFails: true, pauseSave: true)
        let session = make(harness); edit(session, "first")
        let flush = Task { await session.flush() }
        for _ in 0..<200 {
            if await harness.recorded().contains("save") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(session.isSaving)
        edit(session, "newer")
        XCTAssertFalse(session.canKeepRecovery)
        await harness.release()
        _ = await flush.value
        XCTAssertFalse(session.canKeepRecovery); XCTAssertFalse(session.prepareRecoveryClose())
        XCTAssertEqual(session.recoveryDraft?.source, "first")
        _ = await session.flush()
        XCTAssertTrue(session.canKeepRecovery); XCTAssertEqual(session.recoveryDraft?.source, "newer")
    }
    func testSuccessfulSaveRetiresCheckpointAfterReceipt() async {
        let harness = RecoveryHarness(); let session = make(harness); edit(session, "new")
        let result = await session.flush()
        XCTAssertTrue(result); XCTAssertNil(session.recoveryDraft); XCTAssertNil(session.recoveryStatus)
        let events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "complete"])
    }
    func testUncertainRetirementDoesNotAdvertiseRecoveryOrDiscardSavedReceipt() async {
        let harness = RecoveryHarness(); await harness.configure(cleanupFails: true)
        let session = make(harness); edit(session, "saved")
        let result = await session.flush()
        XCTAssertTrue(result); XCTAssertTrue(session.canClose); XCTAssertFalse(session.canKeepRecovery)
        XCTAssertEqual(session.document.baseline, Data("saved".utf8)); XCTAssertFalse(session.dirty)
        XCTAssertTrue(session.errorMessage?.hasPrefix("Document saved.") == true)
        XCTAssertTrue(session.recoveryCleanupPending)
        await harness.configure()
        let retry = await session.flush()
        XCTAssertTrue(retry); XCTAssertFalse(session.recoveryCleanupPending); XCTAssertNil(session.errorMessage)
        let events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "complete", "checkpoint", "save", "complete"])
    }
    func testDurabilityWarningRetainsCheckpointUntilExplicitConfirmedRetry() async {
        let harness = RecoveryHarness(); await harness.configure(warnOnce: true)
        let session = make(harness); edit(session, "saved")
        let result = await session.flush()
        XCTAssertFalse(result); XCTAssertTrue(session.canKeepRecovery)
        XCTAssertEqual(session.document.baseline, Data("saved".utf8))
        var events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save"])
        let retry = await session.flush()
        XCTAssertTrue(retry); XCTAssertNil(session.recoveryDraft)
        events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "checkpoint", "save", "complete"])
    }
    private func waitFor(_ event: String, harness: RecoveryHarness) async throws {
        for _ in 0..<200 {
            if await harness.recorded().contains(event) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Recovery pipeline did not reach \(event)")
    }
    func testCompositionAndNewSourceDuringCheckpointAwaitRemainUnsavedUntilCommit() async throws {
        let harness = RecoveryHarness(); await harness.configure(pauseCheckpoint: true)
        let session = make(harness); edit(session, "first")
        let flush = Task { await session.flush() }
        try await waitFor("checkpoint", harness: harness)
        XCTAssertFalse(session.canKeepRecovery)
        edit(session, "に", composing: true)
        await harness.releaseCheckpoint()
        let result = await flush.value
        XCTAssertFalse(result); XCTAssertTrue(session.dirty); XCTAssertTrue(session.model.composing)
        XCTAssertEqual(session.document.source, "first"); XCTAssertEqual(session.model.source, "に")
        XCTAssertFalse(session.prepareRecoveryClose())
        edit(session, "日本", composing: false)
        let committed = await session.flush()
        XCTAssertTrue(committed); XCTAssertEqual(session.document.source, "日本")
    }
    func testNewEditsDuringRetirementGetTheirOwnCheckpointAndSave() async throws {
        let harness = RecoveryHarness(); await harness.configure(pauseComplete: true)
        let session = make(harness); edit(session, "first")
        let flush = Task { await session.flush() }
        try await waitFor("complete", harness: harness)
        XCTAssertEqual(session.document.source, "first"); XCTAssertFalse(session.canKeepRecovery)
        edit(session, "newest")
        await harness.releaseComplete()
        let result = await flush.value
        XCTAssertTrue(result); XCTAssertEqual(session.document.source, "newest")
        XCTAssertNil(session.recoveryDraft)
        let events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "complete", "checkpoint", "save", "complete"])
    }
    func testCompositionPreventsRecoveryAcknowledgementUntilCommit() async {
        let harness = RecoveryHarness(); let session = make(harness)
        edit(session, "に", composing: true)
        _ = await session.flush()
        XCTAssertFalse(session.prepareRecoveryClose())
        var events = await harness.recorded()
        XCTAssertEqual(events, [])
        edit(session, "日本", composing: false)
        _ = await session.flush()
        events = await harness.recorded()
        XCTAssertEqual(events, ["checkpoint", "save", "complete"])
        XCTAssertEqual(session.document.source, "日本")
    }
}
