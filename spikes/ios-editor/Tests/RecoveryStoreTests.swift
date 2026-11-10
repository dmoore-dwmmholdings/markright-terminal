import XCTest
import Foundation
import CryptoKit
import Darwin
@testable import MarkrightEditorSpike

@MainActor final class RecoveryStoreTests: XCTestCase {
    private func fixture() throws -> (URL, CollectionStore) {
        let root = try NativeTestDirectory.parent()
            .appendingPathComponent("RecoveryStoreTests-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, CollectionStore(root: root))
    }

    private func expect(_ expected: CollectionStoreError, operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CollectionStoreError, expected, file: file, line: line)
        }
    }

    private func expectUnsafe(operation: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected unsafe entry refusal", file: file, line: line)
        } catch CollectionStoreError.unsafeEntry { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }

    private func recoveryFolder(_ root: URL) -> URL {
        root.appendingPathComponent(".markright-recovery", isDirectory: true)
    }

    private func rehash(_ payload: Data) -> Data {
        var result = payload
        result.append(contentsOf: SHA256.hash(data: payload))
        return result
    }

    func testCheckpointReopensExactAuthoredBytesAndLatestSessionToken() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let baseline = "\u{FEFF}baseline\r\nCafe\u{301}\r"
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: baseline)
        let sessionID = UUID()
        let first = try await store.checkpoint(document, source: "first dirty edit", sessionID: sessionID)
        let edited = "\u{FEFF}unsaved 😀\r\nCafe\u{301}\rlast\n"
        let latest = try await store.checkpoint(document, source: edited, sessionID: sessionID)
        XCTAssertNotEqual(first.id, latest.id)
        XCTAssertEqual(first.fileName, latest.fileName)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recoveryFolder(root).path), [latest.fileName])
        let reopened = CollectionStore(root: root)
        let inventory = try await reopened.recoveries()
        XCTAssertTrue(inventory.issues.isEmpty)
        let draft = try XCTUnwrap(inventory.drafts.first)
        XCTAssertEqual(inventory.drafts.count, 1)
        XCTAssertEqual(draft.id, latest.id)
        XCTAssertEqual(draft.sessionID, sessionID)
        XCTAssertEqual(draft.baseline, Data(baseline.utf8))
        XCTAssertEqual(Array(draft.source.utf8), Array(edited.utf8))
        let untouched = try await reopened.open(collection: "Work", name: "notes.mrk")
        XCTAssertEqual(untouched.baseline, Data(baseline.utf8))
        let collections = try await reopened.collections()
        XCTAssertEqual(collections, ["Work"])
    }

    func testStaleAndForgedCompletionCannotRetireLatestCheckpoint() async throws {
        let (_, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "baseline")
        let sessionID = UUID()
        let old = try await store.checkpoint(document, source: "old", sessionID: sessionID)
        let latest = try await store.checkpoint(document, source: "Café", sessionID: sessionID)
        await expect(.conflict) { try await store.completeCheckpoint(old) }
        // Swift String equality treats these spellings as equal. Retirement must
        // compare the actual authored bytes and all origin metadata instead.
        for forged in [
            RecoveryDraft(id: latest.id, sessionID: sessionID, collection: "Work", name: "notes.mrk", source: "Cafe\u{301}", baseline: latest.baseline),
            RecoveryDraft(id: latest.id, sessionID: sessionID, collection: "Other", name: "notes.mrk", source: latest.source, baseline: latest.baseline),
            RecoveryDraft(id: latest.id, sessionID: sessionID, collection: "Work", name: "other.mrk", source: latest.source, baseline: latest.baseline),
            RecoveryDraft(id: latest.id, sessionID: sessionID, collection: "Work", name: "notes.mrk", source: latest.source, baseline: Data("other baseline".utf8))
        ] {
            await expect(.conflict) { try await store.completeCheckpoint(forged) }
        }
        let remaining = try await store.recoveries()
        XCTAssertEqual(remaining.drafts.map(\.id), [latest.id])
        _ = try await store.save(document, source: latest.source)
        try await store.completeCheckpoint(latest)
        try await store.completeCheckpoint(latest) // Missing, already retired is idempotent.
        let empty = try await store.recoveries()
        XCTAssertTrue(empty.drafts.isEmpty)
    }

    func testConflictKeepsRecoveryAndRestorePublishesSeparateCopy() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "baseline")
        let draft = try await store.checkpoint(document, source: "local unsaved\r\n", sessionID: UUID())
        let external = Data("external edit".utf8)
        try external.write(to: root.appendingPathComponent("Work/notes.mrk"))
        await expect(.conflict) { _ = try await store.save(document, source: draft.source) }
        await expect(.collision("NOTES.MRK")) {
            _ = try await store.restoreRecovery(draft, collection: "Work", name: "NOTES.MRK")
        }
        let stillPresent = try await store.recoveries()
        XCTAssertEqual(stillPresent.drafts.map(\.id), [draft.id])
        let receipt = try await store.restoreRecovery(draft, collection: "Work", name: "recovered.mrk")
        XCTAssertNil(receipt.document.durabilityWarning)
        XCTAssertNil(receipt.retirementWarning)
        XCTAssertEqual(receipt.document.baseline, Data(draft.source.utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/notes.mrk")), external)
        let recovered = try await store.open(collection: "Work", name: "recovered.mrk")
        XCTAssertEqual(recovered.baseline, Data(draft.source.utf8))
        let empty = try await store.recoveries()
        XCTAssertTrue(empty.drafts.isEmpty)
    }

    func testRestoreRequiresExactCurrentOnDiskCandidateBeforeCreatingCopy() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk")
        let session = UUID()
        let stale = try await store.checkpoint(document, source: "old", sessionID: session)
        let latest = try await store.checkpoint(document, source: "new", sessionID: session)
        await expect(.conflict) { _ = try await store.restoreRecovery(stale, collection: "Work", name: "copy.mrk") }
        let path = recoveryFolder(root).appendingPathComponent(latest.fileName)
        var corrupted = try Data(contentsOf: path)
        corrupted[corrupted.count - 33] ^= 1
        try corrupted.write(to: path)
        await expect(.malformedRecovery(latest.fileName)) {
            _ = try await store.restoreRecovery(latest, collection: "Work", name: "copy.mrk")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/copy.mrk").path))
        XCTAssertEqual(try Data(contentsOf: path), corrupted)
    }

    func testMalformedUnsafeAndPendingSiblingsArePreservedWithoutHidingValidDrafts() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "base")
        let draft = try await store.checkpoint(document, source: "draft", sessionID: UUID())
        let folder = recoveryFolder(root)
        let valid = try Data(contentsOf: folder.appendingPathComponent(draft.fileName))
        let pendingName = UUID().uuidString + ".pending"
        try valid.write(to: folder.appendingPathComponent(pendingName))
        var cases: [Data] = []
        var checksum = valid
        checksum[checksum.count - 33] ^= 1
        cases.append(checksum)
        cases.append(Data(valid.dropLast()))
        var trailing = Data(valid.dropLast(32))
        trailing.append(0)
        cases.append(rehash(trailing))
        var version = Data(valid.dropLast(32))
        version[11] = 2
        cases.append(rehash(version))
        var badLength = Data(valid.dropLast(32))
        badLength[84] = 0x7F // First collection length, after magic/version/UUIDs.
        cases.append(rehash(badLength))
        var invalidUTF8 = Data(valid.dropLast(32))
        invalidUTF8[invalidUTF8.count - 1] = 0xFF
        cases.append(rehash(invalidUTF8))
        var invalidBaseline = Data(valid.dropLast(32))
        invalidBaseline[100 + document.collection.utf8.count + document.name.utf8.count] = 0xFF
        cases.append(rehash(invalidBaseline))
        var invalidUUID = Data(valid.dropLast(32))
        invalidUUID[12] = 0x3F
        cases.append(rehash(invalidUUID))
        var invalidOrigin = Data(valid.dropLast(32))
        invalidOrigin[100] = 0x2E // Hidden collection name, otherwise valid UTF-8.
        cases.append(rehash(invalidOrigin))
        var invalidExtension = Data(valid.dropLast(32))
        invalidExtension[100 + document.collection.utf8.count + document.name.utf8.count - 1] = 0x78
        cases.append(rehash(invalidExtension))
        // A valid envelope under the wrong session filename is not a candidate.
        let aliasName = UUID().uuidString + ".draft"
        try valid.write(to: folder.appendingPathComponent(aliasName))
        for bytes in cases {
            try bytes.write(to: folder.appendingPathComponent(UUID().uuidString + ".pending"))
        }
        let oversized = folder.appendingPathComponent(UUID().uuidString + ".pending")
        try Data(repeating: 0, count: CollectionStore.maximumRecoveryBytes + 1).write(to: oversized)
        try Data("unknown".utf8).write(to: folder.appendingPathComponent("unknown"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(UUID().uuidString + ".pending"), withIntermediateDirectories: false)
        let linkSource = root.appendingPathComponent("Work/link-source.mrk")
        try Data("external".utf8).write(to: linkSource)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(UUID().uuidString + ".pending"), withDestinationURL: linkSource)
        try FileManager.default.linkItem(at: linkSource, to: folder.appendingPathComponent(UUID().uuidString + ".pending"))
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        let inventory = try await CollectionStore(root: root).recoveries()
        XCTAssertEqual(Set(inventory.drafts.map(\.fileName)), Set([draft.fileName, pendingName]))
        XCTAssertEqual(inventory.issues.count, before.count - 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), before)
        let pending = try XCTUnwrap(inventory.drafts.first(where: { $0.fileName == pendingName }))
        try await store.completeCheckpoint(pending)
        let remaining = try await store.recoveries()
        XCTAssertEqual(remaining.drafts.map(\.fileName), [draft.fileName])
    }

    func testByteBoundsAndRawEntryLimitAreExplicitAndDoNotTruncate() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let maximum = String(repeating: "x", count: CollectionStore.maximumDocumentBytes)
        let document = StoredDocument(collection: "Work", name: "notes.mrk", source: maximum, baseline: Data(maximum.utf8))
        let draft = try await store.checkpoint(document, source: maximum, sessionID: UUID())
        let folder = recoveryFolder(root)
        let data = try Data(contentsOf: folder.appendingPathComponent(draft.fileName))
        XCTAssertLessThanOrEqual(data.count, CollectionStore.maximumRecoveryBytes)
        let reopened = try await store.recoveries()
        XCTAssertEqual(reopened.drafts.first?.baseline.count, CollectionStore.maximumDocumentBytes)
        XCTAssertEqual(reopened.drafts.first?.source.utf8.count, CollectionStore.maximumDocumentBytes)
        await expect(.tooLarge) { _ = try await store.checkpoint(document, source: maximum + "x", sessionID: UUID()) }
        let oversizedBaseline = StoredDocument(collection: "Work", name: "notes.mrk", source: "", baseline: Data(repeating: 0, count: CollectionStore.maximumDocumentBytes + 1))
        await expect(.tooLarge) { _ = try await store.checkpoint(oversizedBaseline, source: "", sessionID: UUID()) }
        let invalidBaseline = StoredDocument(collection: "Work", name: "notes.mrk", source: "", baseline: Data([0xC0, 0xAF]))
        await expect(.invalidUTF8) { _ = try await store.checkpoint(invalidBaseline, source: "", sessionID: UUID()) }
        for _ in 1..<CollectionStore.maximumRecoveryEntries {
            try data.write(to: folder.appendingPathComponent(UUID().uuidString + ".pending"))
        }
        let full = try await store.recoveries()
        XCTAssertEqual(full.drafts.count, CollectionStore.maximumRecoveryEntries)
        await expect(.recoveryLimit) { _ = try await store.checkpoint(document, source: "next", sessionID: draft.sessionID) }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(draft.fileName)), data)
        try Data().write(to: folder.appendingPathComponent("extra"))
        await expect(.recoveryLimit) { _ = try await store.recoveries() }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, CollectionStore.maximumRecoveryEntries + 1)
    }

    func testAbsentInventoryAndOriginMetadataNameBounds() async throws {
        let (root, store) = try fixture()
        let initial = try await store.recoveries()
        XCTAssertTrue(initial.drafts.isEmpty)
        XCTAssertTrue(initial.issues.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryFolder(root).path))
        for collection in ["../escape", ".hidden", "CON", String(repeating: "c", count: 256)] {
            let invalid = StoredDocument(collection: collection, name: "notes.mrk", source: "", baseline: Data())
            await expect(.invalidName(collection)) { _ = try await store.checkpoint(invalid, source: "draft", sessionID: UUID()) }
        }
        for name in ["../escape.mrk", "CON.mrk", "notes.txt", String(repeating: "n", count: 252) + ".mrk"] {
            let invalid = StoredDocument(collection: "Work", name: name, source: "", baseline: Data())
            await expect(.invalidName(name)) { _ = try await store.checkpoint(invalid, source: "draft", sessionID: UUID()) }
        }
        let bounded = StoredDocument(collection: String(repeating: "c", count: 255),
                                     name: String(repeating: "n", count: 251) + ".mrk", source: "", baseline: Data())
        let draft = try await store.checkpoint(bounded, source: "{\"type\":\"script\"}\n<script>inert</script>", sessionID: UUID())
        let inventory = try await store.recoveries()
        XCTAssertEqual(inventory.drafts.first?.source, draft.source)
        XCTAssertEqual(inventory.drafts.first?.collection.utf8.count, 255)
        XCTAssertEqual(inventory.drafts.first?.name.utf8.count, 255)
        let forgedPath = RecoveryDraft(id: draft.id, sessionID: draft.sessionID, fileName: "../escape.draft",
                                      collection: draft.collection, name: draft.name, source: draft.source, baseline: draft.baseline)
        await expect(.malformedRecovery("../escape.draft")) { try await store.completeCheckpoint(forgedPath) }
    }

    func testMetadataFolderDoesNotUseCollectionSlotAndSymlinkIsRefused() async throws {
        let (root, store) = try fixture()
        _ = try await store.collections()
        for index in 0..<CollectionStore.maximumCollections {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("C\(index)"), withIntermediateDirectories: false)
        }
        let document = StoredDocument(collection: "C0", name: "notes.mrk", source: "", baseline: Data())
        _ = try await store.checkpoint(document, source: "edit", sessionID: UUID())
        let collections = try await store.collections()
        XCTAssertEqual(collections.count, CollectionStore.maximumCollections)
        try FileManager.default.removeItem(at: recoveryFolder(root))
        try FileManager.default.createSymbolicLink(at: recoveryFolder(root), withDestinationURL: root.appendingPathComponent("C0"))
        await expectUnsafe { _ = try await store.collections() }
        await expectUnsafe { _ = try await store.recoveries() }
        await expectUnsafe { _ = try await store.checkpoint(document, source: "edit", sessionID: UUID()) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("C0").path).isEmpty)
    }

    func testRecoveryInventoryDoesNotEnumerateUnrelatedMalformedRootEntry() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "baseline")
        let sessionID = UUID()
        _ = try await store.checkpoint(document, source: "first edit", sessionID: sessionID)
        let unrelated = root.appendingPathComponent(".unexpected")
        let preserved = Data("unrelated malformed root entry".utf8)
        try preserved.write(to: unrelated)
        await expect(.invalidName(".unexpected")) { _ = try await store.collections() }
        let draft = try await store.checkpoint(document, source: "latest edit", sessionID: sessionID)
        let inventory = try await CollectionStore(root: root).recoveries()
        XCTAssertEqual(inventory.drafts.map(\.id), [draft.id])
        XCTAssertTrue(inventory.issues.isEmpty)
        XCTAssertEqual(inventory.drafts.first?.source, "latest edit")
        try await store.completeCheckpoint(draft)
        let empty = try await store.recoveries()
        XCTAssertTrue(empty.drafts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: unrelated), preserved)
    }

    func testInterruptedWriteLimitBoundsBothRawEnumerationAndSkippedStages() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let work = root.appendingPathComponent("Work")
        let bytes = Data("preserved".utf8)
        for index in 0..<CollectionStore.maximumDocuments {
            try bytes.write(to: work.appendingPathComponent("D\(index).mrk"))
        }
        var stagingNames: [String] = []
        for _ in 0..<CollectionStore.maximumInterruptedWrites {
            let name = ".markright-write-" + UUID().uuidString
            stagingNames.append(name)
            try bytes.write(to: work.appendingPathComponent(name))
        }
        let documents = try await store.documents(in: "Work")
        XCTAssertEqual(documents.count, CollectionStore.maximumDocuments)
        let interrupted = try await store.interruptedWrites(in: "Work")
        XCTAssertEqual(interrupted, stagingNames.sorted())
        let opened = try await store.open(collection: "Work", name: "D0.mrk")
        XCTAssertEqual(opened.baseline, bytes)
        await expect(.interruptedWriteLimit) { _ = try await store.save(opened, source: "must not publish") }
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("D0.mrk")), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path).count,
                       CollectionStore.maximumCollectionRawEntries)
        let extra = work.appendingPathComponent(".markright-write-" + UUID().uuidString)
        try bytes.write(to: extra)
        await expect(.interruptedWriteLimit) { _ = try await store.documents(in: "Work") }
        await expect(.interruptedWriteLimit) { _ = try await store.interruptedWrites(in: "Work") }
        await expect(.interruptedWriteLimit) { _ = try await store.open(collection: "Work", name: "D0.mrk") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path).count,
                       CollectionStore.maximumCollectionRawEntries + 1)
        XCTAssertEqual(try Data(contentsOf: extra), bytes)
        // Exercise the separate skipped-stage count without reaching the total
        // raw-entry bound: 33 staging files and zero ordinary documents.
        for index in 0..<CollectionStore.maximumDocuments {
            try FileManager.default.removeItem(at: work.appendingPathComponent("D\(index).mrk"))
        }
        await expect(.interruptedWriteLimit) { _ = try await store.documents(in: "Work") }
        await expect(.interruptedWriteLimit) { _ = try await store.interruptedWrites(in: "Work") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path).count,
                       CollectionStore.maximumInterruptedWrites + 1)
        try FileManager.default.removeItem(at: extra)
        await expect(.interruptedWriteLimit) { _ = try await store.createDocument(collection: "Work", name: "new.mrk", source: "must not publish") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: work.path).count,
                       CollectionStore.maximumInterruptedWrites)
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("new.mrk").path))
    }

    func testInterruptedWriteArtifactsRemainVisibleAndPublishedHardlinkCanOpen() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let work = root.appendingPathComponent("Work")
        let stagingName = ".markright-write-" + UUID().uuidString
        let staging = work.appendingPathComponent(stagingName)
        let authored = Data("\u{FEFF}interrupted\r\n".utf8)
        try authored.write(to: staging)
        let emptyDocuments = try await store.documents(in: "Work")
        XCTAssertTrue(emptyDocuments.isEmpty)
        let firstInterrupted = try await store.interruptedWrites(in: "Work")
        XCTAssertEqual(firstInterrupted, [stagingName])
        try FileManager.default.linkItem(at: staging, to: work.appendingPathComponent("published.mrk"))
        let published = try await store.open(collection: "Work", name: "published.mrk")
        XCTAssertEqual(published.baseline, authored)
        let names = try await store.documents(in: "Work")
        XCTAssertEqual(names, ["published.mrk"])
        let interrupted = try await store.interruptedWrites(in: "Work")
        XCTAssertEqual(interrupted, [stagingName])
        XCTAssertEqual(try Data(contentsOf: staging), authored)
        // An extra outside-style link makes the document and staging unsafe.
        try FileManager.default.linkItem(at: staging, to: work.appendingPathComponent("third.mrk"))
        await expectUnsafe { _ = try await store.open(collection: "Work", name: "published.mrk") }
        await expectUnsafe { _ = try await store.interruptedWrites(in: "Work") }
    }

    func testPseudoStagingNamesSymlinksAndArbitraryHardlinksAreRefused() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let work = root.appendingPathComponent("Work")
        let source = work.appendingPathComponent("notes.mrk")
        try Data("keep".utf8).write(to: source)
        let invalid = work.appendingPathComponent(".markright-write-not-a-uuid")
        try Data("keep".utf8).write(to: invalid)
        await expectUnsafe { _ = try await store.documents(in: "Work") }
        await expectUnsafe { _ = try await store.interruptedWrites(in: "Work") }
        try FileManager.default.removeItem(at: invalid)
        let symlink = work.appendingPathComponent(".markright-write-" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        await expectUnsafe { _ = try await store.documents(in: "Work") }
        try FileManager.default.removeItem(at: symlink)
        let arbitrary = work.appendingPathComponent("alias.mrk")
        try FileManager.default.linkItem(at: source, to: arbitrary)
        await expectUnsafe { _ = try await store.open(collection: "Work", name: "notes.mrk") }
        await expectUnsafe { _ = try await store.documents(in: "Work") }
        XCTAssertEqual(try Data(contentsOf: source), Data("keep".utf8))
    }
}
