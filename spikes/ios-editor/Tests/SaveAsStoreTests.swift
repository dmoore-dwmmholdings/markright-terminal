import XCTest
@testable import MarkrightEditorSpike

@MainActor final class SaveAsStoreTests: XCTestCase {
    private func fixture() async throws -> (URL, CollectionStore, StoredDocument, DocumentSession) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("SaveAsStoreTests-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = CollectionStore(root: root)
        try await store.createCollection("Work"); try await store.createCollection("Archive")
        let original = try await store.createDocument(collection: "Work", name: "notes.md", source: "original\r\n")
        let id = UUID()
        let hooks = DocumentRecovery(checkpoint: { try await store.checkpoint($0, source: $1, sessionID: id) }, complete: { try await store.completeCheckpoint($0) })
        let session = DocumentSession(document: original, recovery: hooks) { try await store.save($0, source: $1) }
        return (root, store, original, session)
    }
    private func edit(_ session: DocumentSession, _ source: String) {
        if !session.model.sourceMode { session.model.showSource() }
        session.model.updateDocumentSource(source, composing: false, generation: session.model.editingGeneration)
    }
    func testSaveAsResolvesObservedConflictAndFutureWritesUseNewCollection() async throws {
        let (root, store, _, session) = try await fixture()
        let external = Data("external edit\n".utf8)
        let originalURL = root.appendingPathComponent("Work/notes.md")
        try external.write(to: originalURL)
        let source = "\u{FEFF}my 😀 source\r\nCafe\u{301}\r"
        edit(session, source)
        let oldSave = await session.flush()
        XCTAssertFalse(oldSave); XCTAssertTrue(session.canKeepRecovery)
        let copy = await session.saveAs(collection: "Archive", name: "rescued.md") { try await store.createDocument(collection: $0, name: $1, source: $2) }
        XCTAssertNotNil(copy); XCTAssertTrue(session.canClose)
        XCTAssertEqual(session.document.collection, "Archive")
        XCTAssertEqual(Array(session.model.source.utf8), Array(source.utf8))
        XCTAssertEqual(try Data(contentsOf: originalURL), external)
        let reopened = try await CollectionStore(root: root).open(collection: "Archive", name: "rescued.md")
        XCTAssertEqual(reopened.baseline, Data(source.utf8))
        let inventory = try await store.recoveries()
        XCTAssertTrue(inventory.drafts.isEmpty)
        edit(session, source + "next")
        let saved = await session.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(try Data(contentsOf: originalURL), external)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Archive/rescued.md")), Data((source + "next").utf8))
    }
    func testSaveAsCollisionRetainsOriginalDestinationAndRecovery() async throws {
        let (root, store, original, session) = try await fixture()
        _ = try await store.createDocument(collection: "Archive", name: "existing.md", source: "keep existing")
        edit(session, "unsaved local source")
        let copy = await session.saveAs(collection: "Archive", name: "existing.md") { try await store.createDocument(collection: $0, name: $1, source: $2) }
        XCTAssertNil(copy); XCTAssertNotNil(session.destinationError); XCTAssertTrue(session.dirty)
        XCTAssertEqual(session.document.name, original.name); XCTAssertEqual(session.document.collection, original.collection)
        XCTAssertEqual(session.model.source, "unsaved local source"); XCTAssertTrue(session.canKeepRecovery)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/notes.md")), original.baseline)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Archive/existing.md")), Data("keep existing".utf8))
        let inventory = try await store.recoveries()
        XCTAssertEqual(inventory.drafts.first?.source, "unsaved local source")
    }
    func testInvalidDestinationCannotEscapeOrMutateOriginal() async throws {
        let (root, store, original, session) = try await fixture()
        edit(session, "new")
        let copy = await session.saveAs(collection: "../escape", name: "copy.md") { try await store.createDocument(collection: $0, name: $1, source: $2) }
        XCTAssertNil(copy); XCTAssertEqual(session.document.baseline, original.baseline)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/notes.md")), original.baseline)
        let names = try await store.collections()
        XCTAssertEqual(Set(names), Set(["Archive", "Work"]))
    }
    func testDialogResumptionPreservesSelectionsAndRejectsStaleCallbacks() {
        let model = EditorModel(source: "first 😀\r\nsecond")
        let initial = model.editingGeneration
        model.resumeEditorAfterDialog(); XCTAssertEqual(model.editingGeneration, initial)
        model.showSource()
        let previous = model.editingGeneration
        let range = NSRange(location: 6, length: 2)
        model.updateDocumentSource(model.source, composing: false, generation: previous, selection: range)
        model.resumeEditorAfterDialog()
        XCTAssertGreaterThan(model.editingGeneration, previous); XCTAssertEqual(model.documentSelection, range)
        model.updateDocumentSource("stale", composing: true, generation: previous)
        XCTAssertEqual(model.source, "first 😀\r\nsecond"); XCTAssertFalse(model.composing)
        let current = model.editingGeneration
        model.composing = true; model.resumeEditorAfterDialog(); XCTAssertEqual(model.editingGeneration, current)
        model.composing = false; model.finish(); model.setReadingMode(true)
        let reading = model.editingGeneration
        model.resumeEditorAfterDialog(); XCTAssertEqual(model.editingGeneration, reading)
    }
}
