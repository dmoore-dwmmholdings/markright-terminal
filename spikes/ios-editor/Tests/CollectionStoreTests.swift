import XCTest
import Foundation
import Darwin
@testable import MarkrightEditorSpike

@MainActor final class CollectionStoreTests: XCTestCase {
    private func fixture() throws -> (URL, CollectionStore) {
        // The system temporary-directory spelling can contain /var symlinks.
        // Resolve the trusted parent before passing the app-owned leaf to the store.
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CollectionStoreTests-" + UUID().uuidString, isDirectory: true)
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
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription, file: file, line: line)
        }
    }

    private func expectRefusal(operation: () async throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected unsafe-entry refusal", file: file, line: line)
        } catch CollectionStoreError.unsafeEntry { }
        catch { XCTFail("Unexpected refusal: \(error)", file: file, line: line) }
    }

    func testCreateListSaveAndReopenPreserveAuthoredUTF8Bytes() async throws {
        let (root, store) = try fixture()
        let initialCollections = try await store.collections()
        XCTAssertEqual(initialCollections, [])
        try await store.createCollection("Work")
        let original = "\u{FEFF}first 😀\r\nCafe\u{301}\rlast\n"
        let created = try await store.createDocument(collection: "Work", name: "notes.mrk", source: original)
        XCTAssertEqual(created.baseline, Data(original.utf8))
        XCTAssertEqual(Array(created.source.utf8), Array(original.utf8))
        let names = try await store.documents(in: "Work")
        XCTAssertEqual(names, ["notes.mrk"])
        // Repeated directory enumeration must not inherit an exhausted FD offset.
        let repeatedNames = try await store.documents(in: "Work")
        XCTAssertEqual(repeatedNames, names)
        let opened = try await store.open(collection: "Work", name: "notes.mrk")
        XCTAssertEqual(opened.baseline, created.baseline)
        XCTAssertEqual(Array(opened.source.utf8), Array(original.utf8))
        let changed = "\u{FEFF}changed\r\n```swift\rcode\n```\r"
        let saved = try await store.save(opened, source: changed)
        XCTAssertEqual(saved.baseline, Data(changed.utf8))
        XCTAssertEqual(saved.source, changed)
        let reopened = try await CollectionStore(root: root).open(collection: "Work", name: "notes.mrk")
        XCTAssertEqual(reopened.baseline, saved.baseline)
        XCTAssertEqual(Array(reopened.source.utf8), Array(changed.utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/notes.mrk")), Data(changed.utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Work").path), ["notes.mrk"])
    }

    func testInvalidNamesAndExtensionsCannotEscapeTheOwnedRoot() async throws {
        let (_, store) = try fixture()
        try await store.createCollection("Work")
        for name in ["", ".", "..", ".hidden", "../escape", "a/b", "a\\b", "a:b", "trailing.", "trailing ", "line\nfeed", "zero\u{0}", "CON", "aux", "COM1", "lpt9", "COM¹", "LPT³", "a|b", "a?b", String(repeating: "x", count: 256)] {
            await expect(.invalidName(name)) { try await store.createCollection(name) }
            await expect(.invalidName(name)) { _ = try await store.documents(in: name) }
        }
        for name in ["", ".md", ".hidden.mrk", "../escape.md", "a/b.md", "a\\b.mrk", "CON.md", "NUL.mrk", "COM3.md", "notes.txt", "notes", "notes.md.", "notes.mrk ", "a\t.md"] {
            await expect(.invalidName(name)) { _ = try await store.createDocument(collection: "Work", name: name) }
            await expect(.invalidName(name)) { _ = try await store.open(collection: "Work", name: name) }
        }
        let empty = try await store.createDocument(collection: "Work", name: "empty.md")
        XCTAssertTrue(empty.source.isEmpty)
        XCTAssertTrue(empty.baseline.isEmpty)
        let names = try await store.documents(in: "Work")
        XCTAssertEqual(names, ["empty.md"])
    }

    func testCaseAndCanonicalUnicodeCollisionsNeverOverwrite() async throws {
        let (_, store) = try fixture()
        try await store.createCollection("Café")
        await expect(.collision("CAFE\u{301}")) { try await store.createCollection("CAFE\u{301}") }
        _ = try await store.createDocument(collection: "Café", name: "Résumé.mrk", source: "keep")
        for name in ["Résumé.mrk", "RÉSUMÉ.MRK", "Re\u{301}sume\u{301}.mrk"] {
            await expect(.collision(name)) { _ = try await store.createDocument(collection: "Café", name: name, source: "overwrite") }
        }
        let opened = try await store.open(collection: "Café", name: "Résumé.mrk")
        XCTAssertEqual(opened.source, "keep")
        let collections = try await store.collections()
        let documents = try await store.documents(in: "Café")
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(documents.count, 1)
    }

    func testRootAndAncestorSymlinksAreRefused() async throws {
        let (root, _) = try fixture()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await expectRefusal { _ = try await CollectionStore(root: link).collections() }
        await expectRefusal { _ = try await CollectionStore(root: link.appendingPathComponent("Nested")).collections() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("Nested").path))
    }

    func testCollectionAndDocumentSymlinksAndHardlinksAreRefused() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let work = root.appendingPathComponent("Work", isDirectory: true)
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mrk")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = work.appendingPathComponent("linked.mrk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await expectRefusal { _ = try await store.open(collection: "Work", name: "linked.mrk") }
        await expectRefusal { _ = try await store.documents(in: "Work") }
        let forged = StoredDocument(collection: "Work", name: "linked.mrk", source: "outside", baseline: Data("outside".utf8))
        await expectRefusal { _ = try await store.save(forged, source: "overwrite") }
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.linkItem(at: outside, to: link)
        await expectRefusal { _ = try await store.open(collection: "Work", name: "linked.mrk") }
        try FileManager.default.removeItem(at: link)
        let collectionLink = root.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: collectionLink, withDestinationURL: work)
        await expectRefusal { _ = try await store.collections() }
        await expectRefusal { _ = try await store.documents(in: "Alias") }
        await expectRefusal { _ = try await store.createDocument(collection: "Alias", name: "escape.mrk") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("escape.mrk").path))
    }

    func testInvalidUTF8AndOversizedFilesAreRejectedWithoutRewriting() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let work = root.appendingPathComponent("Work", isDirectory: true)
        let invalid = Data([0xEF, 0xBB, 0xBF, 0x61, 0xC0, 0xAF, 0xFF])
        let invalidURL = work.appendingPathComponent("invalid.mrk")
        try invalid.write(to: invalidURL)
        await expect(.invalidUTF8) { _ = try await store.open(collection: "Work", name: "invalid.mrk") }
        XCTAssertEqual(try Data(contentsOf: invalidURL), invalid)
        let oversized = Data(repeating: 0x61, count: CollectionStore.maximumDocumentBytes + 1)
        let oversizedURL = work.appendingPathComponent("large.md")
        try oversized.write(to: oversizedURL)
        await expect(.tooLarge) { _ = try await store.open(collection: "Work", name: "large.md") }
        await expect(.tooLarge) { _ = try await store.createDocument(collection: "Work", name: "new.mrk", source: String(repeating: "x", count: CollectionStore.maximumDocumentBytes + 1)) }
        XCTAssertEqual(try Data(contentsOf: oversizedURL), oversized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("new.mrk").path))
        let exact = String(repeating: "😀", count: CollectionStore.maximumDocumentBytes / 4)
        let document = try await store.createDocument(collection: "Work", name: "boundary.mrk", source: exact)
        XCTAssertEqual(document.baseline.count, CollectionStore.maximumDocumentBytes)
        let opened = try await store.open(collection: "Work", name: "boundary.mrk")
        XCTAssertEqual(opened.baseline, document.baseline)
        await expect(.tooLarge) { _ = try await store.save(opened, source: exact + "x") }
        let unchanged = try await store.open(collection: "Work", name: "boundary.mrk")
        XCTAssertEqual(unchanged.baseline, opened.baseline)
    }

    func testExternalByteChangeConflictsAndKeepsExistingFileAndEditorsBaseline() async throws {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        let original = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "original\r\n")
        let url = root.appendingPathComponent("Work/notes.mrk")
        let changed = Data("changed externally\n".utf8)
        try changed.write(to: url)
        await expect(.conflict) { _ = try await store.save(original, source: "local edit") }
        XCTAssertEqual(try Data(contentsOf: url), changed)
        XCTAssertEqual(original.baseline, Data("original\r\n".utf8))
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["notes.mrk"])
    }

    func testConcurrentSavesFromOneBaselineHaveOneWinnerAndOneConflict() async throws {
        let (_, store) = try fixture()
        try await store.createCollection("Work")
        let document = try await store.createDocument(collection: "Work", name: "notes.mrk", source: "original")
        let outcomes = await withTaskGroup(of: Result<StoredDocument, CollectionStoreError>.self) { group in
            for source in ["first", "second"] {
                group.addTask {
                    do { return .success(try await store.save(document, source: source)) }
                    catch let error as CollectionStoreError { return .failure(error) }
                    catch { return .failure(.io(operation: "unexpected test failure", code: -1)) }
                }
            }
            var results: [Result<StoredDocument, CollectionStoreError>] = []
            for await result in group { results.append(result) }
            return results
        }
        let winners = outcomes.compactMap { try? $0.get() }
        let failures: [CollectionStoreError] = outcomes.compactMap { if case .failure(let error) = $0 { return error }; return nil }
        XCTAssertEqual(winners.count, 1)
        XCTAssertEqual(failures, [.conflict])
        let winner = try XCTUnwrap(winners.first)
        let reopened = try await store.open(collection: "Work", name: "notes.mrk")
        XCTAssertEqual(reopened.baseline, winner.baseline)
        XCTAssertEqual(reopened.source, winner.source)
        let next = try await store.save(winner, source: "saved with fresh baseline")
        XCTAssertEqual(next.source, "saved with fresh baseline")
    }

    func testConcurrentSameNameCreationHasOneWinnerWithoutClobbering() async throws {
        let (_, store) = try fixture()
        try await store.createCollection("Work")
        let outcomes = await withTaskGroup(of: Result<StoredDocument, CollectionStoreError>.self) { group in
            for source in ["first", "second"] {
                group.addTask {
                    do { return .success(try await store.createDocument(collection: "Work", name: "notes.mrk", source: source)) }
                    catch let error as CollectionStoreError { return .failure(error) }
                    catch { return .failure(.io(operation: "unexpected test failure", code: -1)) }
                }
            }
            var results: [Result<StoredDocument, CollectionStoreError>] = []
            for await result in group { results.append(result) }
            return results
        }
        let winners = outcomes.compactMap { try? $0.get() }
        let failures: [CollectionStoreError] = outcomes.compactMap { if case .failure(let error) = $0 { return error }; return nil }
        XCTAssertEqual(winners.count, 1)
        XCTAssertEqual(failures, [.collision("notes.mrk")])
        let winner = try XCTUnwrap(winners.first)
        let reopened = try await store.open(collection: "Work", name: "notes.mrk")
        XCTAssertEqual(reopened.baseline, winner.baseline)
    }

    func testCollectionAndDocumentCountLimitsIncludePreexistingEntries() async throws {
        let (root, store) = try fixture()
        // Seed through the filesystem to test reopen/enumeration boundaries without
        // forcing hundreds of unrelated synchronous durability barriers in the test.
        _ = try await store.collections()
        for index in 0..<CollectionStore.maximumCollections {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("C\(index)"), withIntermediateDirectories: false)
        }
        let names = try await store.collections()
        XCTAssertEqual(names.count, CollectionStore.maximumCollections)
        await expect(.collectionLimit) { try await store.createCollection("Overflow") }
        let collection = root.appendingPathComponent("C0")
        for index in 0..<CollectionStore.maximumDocuments {
            try Data().write(to: collection.appendingPathComponent("D\(index).mrk"))
        }
        let documents = try await store.documents(in: "C0")
        XCTAssertEqual(documents.count, CollectionStore.maximumDocuments)
        await expect(.documentLimit) { _ = try await store.createDocument(collection: "C0", name: "Overflow.mrk") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: collection.appendingPathComponent("Overflow.mrk").path))
        try Data().write(to: collection.appendingPathComponent("Extra.mrk"))
        await expect(.documentLimit) { _ = try await store.documents(in: "C0") }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Extra"), withIntermediateDirectories: false)
        await expect(.collectionLimit) { _ = try await store.collections() }
    }
}
