import XCTest
@testable import MarkrightEditorSpike

private actor SaveHarness {
    var calls: [(Data, String)] = []
    var fail = false
    var paused = false
    var warnOnce = false
    private var continuation: CheckedContinuation<Void, Never>?
    func setWarning() { warnOnce = true }
    func setPaused(_ value: Bool) { paused = value }
    func setFail(_ value: Bool) { fail = value }
    func release() { paused = false; continuation?.resume(); continuation = nil }
    func count() -> Int { calls.count }
    func baselines() -> [Data] { calls.map(\.0) }
    func save(_ document: StoredDocument, source: String) async throws -> StoredDocument {
        calls.append((document.baseline, source))
        if paused { await withCheckedContinuation { continuation = $0 } }
        if fail { throw CocoaError(.fileWriteNoPermission) }
        let warning = warnOnce ? "Write committed; durability is uncertain." : nil
        warnOnce = false
        return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: Data(source.utf8), durabilityWarning: warning)
    }
}

@MainActor final class DocumentSessionTests: XCTestCase {
    private func make(_ harness: SaveHarness) -> DocumentSession {
        DocumentSession(document: StoredDocument(collection: "Notes", name: "note.mrk", source: "original", baseline: Data("original".utf8))) {
            try await harness.save($0, source: $1)
        }
    }
    private func edit(_ session: DocumentSession, _ source: String, composing: Bool = false) {
        if !session.model.sourceMode { session.model.showSource() }
        session.model.updateDocumentSource(source, composing: composing, generation: session.model.editingGeneration)
    }
    private func waitForCalls(_ count: Int, _ harness: SaveHarness) async {
        for _ in 0..<1000 {
            if await harness.count() >= count { return }
            await Task.yield()
        }
        XCTFail("Save pump did not start")
    }
    func testInFlightSaveAdvancesBaselineThenSavesNewestSource() async {
        let harness = SaveHarness()
        await harness.setPaused(true)
        let session = make(harness)
        edit(session, "first\r\n")
        let flush = Task { await session.flush() }
        await waitForCalls(1, harness)
        edit(session, "\u{FEFF}newest 😀\r\n")
        let secondFlush = Task { await session.flush() }
        await harness.release()
        let firstResult = await flush.value
        let secondResult = await secondFlush.value
        XCTAssertTrue(firstResult); XCTAssertTrue(secondResult)
        XCTAssertTrue(session.canClose)
        XCTAssertEqual(Array(session.document.source.utf8), Array("\u{FEFF}newest 😀\r\n".utf8))
        let baselines = await harness.baselines()
        XCTAssertEqual(baselines, [Data("original".utf8), Data("first\r\n".utf8)])
    }
    func testFailedSaveKeepsSourceAndRetryUsesUnchangedBaseline() async {
        let harness = SaveHarness()
        await harness.setFail(true)
        let session = make(harness)
        edit(session, "unsaved\rnew")
        let firstResult = await session.flush()
        XCTAssertFalse(firstResult); XCTAssertFalse(session.canClose); XCTAssertTrue(session.dirty)
        XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(session.model.source, "unsaved\rnew")
        XCTAssertEqual(session.document.baseline, Data("original".utf8))
        await harness.setFail(false)
        let retry = await session.flush()
        XCTAssertTrue(retry); XCTAssertNil(session.errorMessage)
        let baselines = await harness.baselines()
        XCTAssertEqual(baselines, [Data("original".utf8), Data("original".utf8)])
    }
    func testCompositionDefersSaveAndCloseUntilCommit() async {
        let harness = SaveHarness()
        let session = make(harness)
        edit(session, "に", composing: true)
        let composingResult = await session.flush()
        let count = await harness.count()
        XCTAssertFalse(composingResult); XCTAssertEqual(count, 0)
        edit(session, "日本", composing: false)
        let committedResult = await session.flush()
        XCTAssertTrue(committedResult); XCTAssertEqual(session.document.source, "日本")
    }
    func testCompositionStartedDuringWriteRetainsNewTextUntilCommit() async {
        let harness = SaveHarness()
        await harness.setPaused(true)
        let session = make(harness)
        edit(session, "first")
        let flush = Task { await session.flush() }
        await waitForCalls(1, harness)
        edit(session, "に", composing: true)
        await harness.release()
        let initial = await flush.value
        XCTAssertFalse(initial); XCTAssertTrue(session.dirty)
        XCTAssertEqual(session.document.source, "first")
        XCTAssertEqual(session.model.source, "に")
        edit(session, "日本", composing: false)
        let committed = await session.flush()
        XCTAssertTrue(committed); XCTAssertEqual(session.document.source, "日本")
    }
    func testDebounceCoalescesEditsAndFlushCancelsPendingDelay() async throws {
        let harness = SaveHarness()
        let session = make(harness)
        edit(session, "one"); session.scheduleSave()
        edit(session, "two"); session.scheduleSave()
        edit(session, "three"); session.scheduleSave()
        let result = await session.flush()
        XCTAssertTrue(result)
        try await Task.sleep(for: .milliseconds(400))
        let count = await harness.count()
        XCTAssertEqual(count, 1); XCTAssertEqual(session.document.source, "three")
    }
    func testCommittedWarningAdvancesBaselineAndStopsAutomaticRetry() async {
        let harness = SaveHarness()
        await harness.setWarning()
        let session = make(harness)
        edit(session, "committed")
        let result = await session.flush()
        XCTAssertFalse(result); XCTAssertFalse(session.dirty); XCTAssertFalse(session.canClose)
        XCTAssertEqual(session.document.baseline, Data("committed".utf8))
        let count = await harness.count()
        XCTAssertEqual(count, 1)
        let retried = await session.flush()
        XCTAssertTrue(retried)
        let baselines = await harness.baselines()
        XCTAssertEqual(baselines, [Data("original".utf8), Data("committed".utf8)])
    }
    func testDurabilityWarningKeepsCloseBlockedUntilExplicitRetry() async {
        let harness = SaveHarness()
        let document = StoredDocument(collection: "Notes", name: "note.mrk", source: "new", baseline: Data("new".utf8), durabilityWarning: "Write committed; durability is uncertain.")
        let session = DocumentSession(document: document) { try await harness.save($0, source: $1) }
        XCTAssertFalse(session.canClose); XCTAssertFalse(session.dirty)
        let result = await session.flush()
        XCTAssertTrue(result); XCTAssertNil(session.document.durabilityWarning)
    }
}
