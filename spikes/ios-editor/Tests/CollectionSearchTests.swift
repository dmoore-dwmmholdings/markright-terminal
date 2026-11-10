import XCTest
import Foundation
@testable import MarkrightEditorSpike

@MainActor final class CollectionSearchTests: XCTestCase {
    private func fixture() throws -> (URL, CollectionStore) {
        let root = try NativeTestDirectory.parent()
            .appendingPathComponent("CollectionSearchTests-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, CollectionStore(root: root))
    }

    private func populated(_ files: [String: Data]) async throws -> (URL, CollectionStore) {
        let (root, store) = try fixture()
        try await store.createCollection("Work")
        for (name, bytes) in files {
            try bytes.write(to: root.appendingPathComponent("Work").appendingPathComponent(name))
        }
        return (root, store)
    }

    private func expectStoreError(_ expected: CollectionStoreError, store: CollectionStore,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await store.searchSavedSource(in: "Work", query: "needle")
            XCTFail("Expected refusal", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CollectionStoreError, expected, file: file, line: line)
        }
    }

    private func tree(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let url as URL in enumerator {
            let path = String(url.path.dropFirst(root.path.count + 1))
            result[path] = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true ? Data() : Data(contentsOf: url)
        }
        return result
    }

    func testLimitsClampZeroAndHardCeilingsWithoutIntegerOverflow() {
        let large = CollectionSearchLimits(maxDocuments: .max, maxBytes: .max, maxResults: .max, maxMatchesPerDocument: .max)
        XCTAssertEqual(large.maxDocuments, 64)
        XCTAssertEqual(large.maxBytes, 8 * 1_048_576)
        XCTAssertEqual(large.maxResults, 50)
        XCTAssertEqual(large.maxMatchesPerDocument, 100)
        let negative = CollectionSearchLimits(maxDocuments: .min, maxBytes: .min, maxResults: .min, maxMatchesPerDocument: .min)
        XCTAssertEqual(negative.maxDocuments, 0)
        XCTAssertEqual(negative.maxBytes, 0)
        XCTAssertEqual(negative.maxResults, 0)
        XCTAssertEqual(negative.maxMatchesPerDocument, 0)
    }

    func testInvalidQueriesFailBeforeAnyRootIOAndUTF16BoundIsExplicit() async throws {
        let (root, store) = try fixture()
        for (query, expected) in [("", CollectionSearchQueryError.empty),
                                  (String(repeating: "x", count: 257), .tooLong),
                                  (String(repeating: "😀", count: 129), .tooLong)] {
            do {
                _ = try await store.searchSavedSource(in: "Work", query: query)
                XCTFail("Expected query validation before missing-root inspection")
            } catch {
                XCTAssertEqual(error as? CollectionSearchQueryError, expected)
                XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let boundary = String(repeating: "😀", count: 128)
        try await store.createCollection("Work")
        _ = try await store.createDocument(collection: "Work", name: "boundary.md", source: boundary)
        let report = try await store.searchSavedSource(in: "Work", query: boundary)
        XCTAssertEqual(report.hits.first?.matchCount, 1)
    }

    func testCanonicalUnicodeCaseBOMAndMixedLineEndingsArePreserved() async throws {
        let source = "\u{FEFF}Café\r\nCAFE\u{301}\r😀 café\n"
        let (root, store) = try await populated(["notes.MRK": Data(source.utf8)])
        let report = try await store.searchSavedSource(in: "Work", query: "CAFÉ")
        XCTAssertEqual(report.collection, "Work")
        XCTAssertEqual(report.query, "CAFÉ")
        XCTAssertEqual(report.totalDocuments, 1)
        XCTAssertEqual(report.inspectedDocuments, 1)
        XCTAssertEqual(report.searchedDocuments, 1)
        XCTAssertEqual(report.processedBytes, source.utf8.count)
        XCTAssertEqual(report.hits.first?.name, "notes.MRK")
        XCTAssertEqual(report.hits.first?.id, "notes.MRK")
        XCTAssertEqual(report.hits.first?.matchCount, 3)
        XCTAssertEqual(report.hits.first?.moreMatches, false)
        XCTAssertEqual(report.hits.first?.preview, String(source.dropFirst()))
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.limited)
        let distinctAccent = try await store.searchSavedSource(in: "Work", query: "cafe")
        XCTAssertTrue(distinctAccent.hits.isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Work/notes.MRK")), Data(source.utf8))
    }

    func testQueriesAreLiteralNonoverlappingAndWhitespaceIsSearchable() async throws {
        let (_, store) = try await populated(["notes.md": Data("a.b A.B axb aaaa  ".utf8)])
        let punctuation = try await store.searchSavedSource(in: "Work", query: "a.b")
        XCTAssertEqual(punctuation.hits.first?.matchCount, 2)
        let overlaps = try await store.searchSavedSource(in: "Work", query: "aa")
        XCTAssertEqual(overlaps.hits.first?.matchCount, 2)
        let whitespace = try await store.searchSavedSource(in: "Work", query: "  ")
        XCTAssertEqual(whitespace.hits.first?.matchCount, 1)
    }

    func testOnlySavedSourceIsSearchedAndNoMetadataOrBytesChange() async throws {
        let (root, store) = try await populated(["needle.md": Data("quiet".utf8), "source.mrk": Data("needle [link](https://example.invalid/)".utf8)])
        let document = try await store.open(collection: "Work", name: "needle.md")
        _ = try await store.checkpoint(document, source: "recovery-only-term", sessionID: UUID())
        let staged = root.appendingPathComponent("Work/.markright-write-" + UUID().uuidString)
        try Data("recovery-only-term needle".utf8).write(to: staged)
        try await store.createCollection("Assets")
        _ = try await store.createDocument(collection: "Assets", name: "elsewhere.md", source: "recovery-only-term")
        let before = try tree(root)
        let report = try await store.searchSavedSource(in: "Work", query: "needle")
        XCTAssertEqual(report.totalDocuments, 2)
        XCTAssertEqual(report.hits.map(\.name), ["source.mrk"])
        XCTAssertEqual(report.hits.first?.preview, "needle [link](https://example.invalid/)")
        let privateContent = try await store.searchSavedSource(in: "Work", query: "recovery-only-term")
        XCTAssertTrue(privateContent.hits.isEmpty)
        XCTAssertFalse(privateContent.limited)
        XCTAssertEqual(try tree(root), before)
    }

    func testHiddenFilesAndAssetsRefuseEnumerationRatherThanBeingSearched() async throws {
        for name in [".hidden.md", "image.png", "assets"] {
            let (root, store) = try await populated(["notes.md": Data("needle".utf8)])
            let path = root.appendingPathComponent("Work").appendingPathComponent(name)
            if name == "assets" {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            } else {
                try Data("needle".utf8).write(to: path)
            }
            await expectStoreError(.invalidName(name), store: store)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    func testMissingAndDeletedRootsAreNeverRecreatedBySearchOrReadOnlyOpens() async throws {
        let (root, store) = try fixture()
        for removedExistingRoot in [false, true] {
            if removedExistingRoot {
                try await store.createCollection("Work")
                _ = try await store.createDocument(collection: "Work", name: "notes.md", source: "needle")
                try FileManager.default.removeItem(at: root)
            }
            do {
                _ = try await store.searchSavedSource(in: "Work", query: "needle")
                XCTFail("Missing root must be refused")
            } catch CollectionStoreError.unsafeEntry { }
            do {
                _ = try await store.documents(in: "Work", createRootIfMissing: false)
                XCTFail("Missing root must be refused")
            } catch CollectionStoreError.unsafeEntry { }
            do {
                _ = try await store.open(collection: "Work", name: "notes.md", createRootIfMissing: false)
                XCTFail("Missing root must be refused")
            } catch CollectionStoreError.unsafeEntry { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testDefaultReadBehaviorStillCreatesMissingRoot() async throws {
        let (root, store) = try fixture()
        do {
            _ = try await store.documents(in: "Work")
            XCTFail("The missing collection must be refused")
        } catch CollectionStoreError.notFound("Work") { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.removeItem(at: root)
        do {
            _ = try await store.open(collection: "Work", name: "notes.md")
            XCTFail("The missing collection must be refused")
        } catch CollectionStoreError.notFound("Work") { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testByteBudgetReservesWholeDocumentBeforeEveryRead() async throws {
        let (_, store) = try await populated(["a.md": Data("x".utf8), "b.md": Data("x".utf8)])
        let maximum = CollectionStore.maximumDocumentBytes
        let none = try await store.searchSavedSource(in: "Work", query: "x", limits: .init(maxBytes: maximum - 1))
        XCTAssertEqual(none.inspectedDocuments, 0)
        XCTAssertEqual(none.processedBytes, 0)
        XCTAssertTrue(none.limited)
        let one = try await store.searchSavedSource(in: "Work", query: "x", limits: .init(maxBytes: maximum))
        XCTAssertEqual(one.inspectedDocuments, 1)
        XCTAssertEqual(one.processedBytes, 1)
        XCTAssertEqual(one.hits.map(\.name), ["a.md"])
        XCTAssertTrue(one.limited)
        let both = try await store.searchSavedSource(in: "Work", query: "x", limits: .init(maxBytes: maximum + 1))
        XCTAssertEqual(both.inspectedDocuments, 2)
        XCTAssertEqual(both.processedBytes, 2)
        XCTAssertFalse(both.limited)
    }

    func testFailedReadConsumesFullReservationAndCannotEscapeBudget() async throws {
        let (_, store) = try await populated(["a.md": Data([0xFF]), "b.md": Data("needle".utf8)])
        let report = try await store.searchSavedSource(in: "Work", query: "needle", limits: .init(maxBytes: CollectionStore.maximumDocumentBytes))
        XCTAssertEqual(report.totalDocuments, 2)
        XCTAssertEqual(report.inspectedDocuments, 1)
        XCTAssertEqual(report.searchedDocuments, 0)
        XCTAssertEqual(report.processedBytes, CollectionStore.maximumDocumentBytes)
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertTrue(report.issues[0].contains("a.md"))
        XCTAssertTrue(report.hits.isEmpty)
        XCTAssertTrue(report.limited)
    }

    func testInvalidUTF8AndOversizedFilesReportIssuesThenContinueWithoutWrites() async throws {
        let invalid = Data([0xEF, 0xBB, 0xBF, 0xC0, 0xAF, 0xFF])
        let large = Data(repeating: 0x61, count: CollectionStore.maximumDocumentBytes + 1)
        let (root, store) = try await populated(["a-invalid.md": invalid, "b-large.md": large, "c-good.md": Data("needle".utf8)])
        let before = try tree(root)
        let report = try await store.searchSavedSource(in: "Work", query: "needle")
        XCTAssertEqual(report.inspectedDocuments, 3)
        XCTAssertEqual(report.searchedDocuments, 1)
        XCTAssertEqual(report.processedBytes, 2 * CollectionStore.maximumDocumentBytes + 6)
        XCTAssertEqual(report.hits.map(\.name), ["c-good.md"])
        XCTAssertEqual(report.issues.count, 2)
        XCTAssertTrue(report.issues[0].contains("valid UTF-8"))
        XCTAssertTrue(report.issues[1].contains("1 MiB"))
        XCTAssertFalse(report.limited)
        XCTAssertEqual(try tree(root), before)
    }

    func testDefaultByteBudgetStopsAfterEightFailedReservations() async throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<9).map { ("\($0).md", Data([0xFF])) })
        let (_, store) = try await populated(files)
        let report = try await store.searchSavedSource(in: "Work", query: "needle")
        XCTAssertEqual(report.totalDocuments, 9)
        XCTAssertEqual(report.inspectedDocuments, 8)
        XCTAssertEqual(report.searchedDocuments, 0)
        XCTAssertEqual(report.processedBytes, 8 * 1_048_576)
        XCTAssertEqual(report.issues.count, 8)
        XCTAssertTrue(report.limited)
    }

    func testZeroBudgetsReturnExplicitLimitationsWithoutOpeningSource() async throws {
        let (_, store) = try await populated(["invalid.md": Data([0xFF])])
        for limits in [CollectionSearchLimits(maxDocuments: 0), .init(maxBytes: 0),
                       .init(maxResults: 0), .init(maxMatchesPerDocument: 0)] {
            let report = try await store.searchSavedSource(in: "Work", query: "needle", limits: limits)
            XCTAssertEqual(report.totalDocuments, 1)
            XCTAssertEqual(report.inspectedDocuments, 0)
            XCTAssertEqual(report.searchedDocuments, 0)
            XCTAssertEqual(report.processedBytes, 0)
            XCTAssertTrue(report.hits.isEmpty)
            XCTAssertTrue(report.issues.isEmpty)
            XCTAssertTrue(report.limited)
        }
    }

    func testDocumentCeilingAndResultFileCeilingAreIndependent() async throws {
        let files = Dictionary(uniqueKeysWithValues: (0..<65).map { (String(format: "%03d.md", $0), Data("needle".utf8)) })
        let (_, store) = try await populated(files)
        let documentBound = try await store.searchSavedSource(in: "Work", query: "absent", limits: .init(maxDocuments: .max))
        XCTAssertEqual(documentBound.totalDocuments, 65)
        XCTAssertEqual(documentBound.inspectedDocuments, 64)
        XCTAssertEqual(documentBound.searchedDocuments, 64)
        XCTAssertTrue(documentBound.hits.isEmpty)
        XCTAssertTrue(documentBound.limitations.contains(where: { $0.contains("document limit (64)") }))
        let resultBound = try await store.searchSavedSource(in: "Work", query: "needle", limits: .init(maxResults: .max))
        XCTAssertEqual(resultBound.inspectedDocuments, 50)
        XCTAssertEqual(resultBound.hits.count, 50)
        XCTAssertEqual(resultBound.hits.first?.name, "000.md")
        XCTAssertEqual(resultBound.hits.last?.name, "049.md")
        XCTAssertTrue(resultBound.limitations.contains(where: { $0.contains("result file limit (50)") }))
    }

    func testExactlyReachedBoundsDoNotFalselyClaimOmittedFilesOrMatches() async throws {
        let (_, store) = try await populated(["notes.md": Data("needle needle".utf8)])
        let report = try await store.searchSavedSource(in: "Work", query: "needle",
                                                     limits: .init(maxDocuments: 1, maxBytes: CollectionStore.maximumDocumentBytes,
                                                                   maxResults: 1, maxMatchesPerDocument: 2))
        XCTAssertEqual(report.hits.first?.matchCount, 2)
        XCTAssertEqual(report.hits.first?.moreMatches, false)
        XCTAssertFalse(report.limited)
    }

    func testMatchCapProbesOneExtraAndHardCeilingIsEnforced() async throws {
        let (_, store) = try await populated(["notes.md": Data(String(repeating: "needle ", count: 101).utf8)])
        for (limit, expected) in [(2, 2), (Int.max, 100)] {
            let report = try await store.searchSavedSource(in: "Work", query: "needle", limits: .init(maxMatchesPerDocument: limit))
            XCTAssertEqual(report.hits.count, 1)
            XCTAssertEqual(report.hits.first?.matchCount, expected)
            XCTAssertEqual(report.hits.first?.moreMatches, true)
            XCTAssertTrue(report.limited)
            XCTAssertEqual(report.inspectedDocuments, 1)
        }
    }

    func testPreviewBoundsDoNotSplitSurrogatesOrCRLFAndStartAtFirstMatch() async throws {
        let (_, store) = try await populated([
            "a-surrogate.md": Data((String(repeating: "a", count: 159) + "😀tail").utf8),
            "b-crlf.md": Data((String(repeating: "a", count: 159) + "\r\ntail").utf8),
            "c-late.md": Data((String(repeating: "x", count: 200) + "a😀\r\nend").utf8)
        ])
        let report = try await store.searchSavedSource(in: "Work", query: "a", limits: .init(maxMatchesPerDocument: 100))
        let previews = Dictionary(uniqueKeysWithValues: report.hits.map { ($0.name, $0.preview) })
        XCTAssertEqual(previews["a-surrogate.md"], String(repeating: "a", count: 159) + "…")
        XCTAssertEqual(previews["b-crlf.md"], String(repeating: "a", count: 159) + "…")
        XCTAssertEqual(previews["c-late.md"], "a😀\r\nend")
        for hit in report.hits {
            XCTAssertLessThanOrEqual(hit.preview.utf16.count, 161)
            XCTAssertFalse(hit.preview.contains("�"))
        }
        let lineFeed = try await store.searchSavedSource(in: "Work", query: "\n")
        XCTAssertEqual(lineFeed.hits.first?.preview, "\r\ntail")
    }

    func testSymlinkHardlinkAndCollectionSymlinkRefuseUnsafeEnumeration() async throws {
        for hardlink in [false, true] {
            let (root, store) = try await populated(["notes.md": Data("needle".utf8)])
            try await store.createCollection("Outside")
            let original = root.appendingPathComponent("Outside/original.md")
            let alias = root.appendingPathComponent("Work/alias.md")
            try Data("needle".utf8).write(to: original)
            if hardlink {
                try FileManager.default.linkItem(at: original, to: alias)
            } else {
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
            }
            await expectStoreError(.unsafeEntry("alias.md"), store: store)
            XCTAssertEqual(try Data(contentsOf: original), Data("needle".utf8))
        }
        let (root, store) = try fixture()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Target"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Work"), withDestinationURL: root.appendingPathComponent("Target"))
        await expectStoreError(.unsafeEntry("Work"), store: store)
    }

    func testCancelledSearchThrowsBeforeAnyMissingRootIO() async throws {
        let (root, store) = try fixture()
        let task = Task { try await store.searchSavedSource(in: "Work", query: "needle") }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled search must not return a completed report")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testEmptyCollectionReturnsCompleteEmptyReport() async throws {
        let (_, store) = try await populated([:])
        let report = try await store.searchSavedSource(in: "Work", query: "needle")
        XCTAssertEqual(report.totalDocuments, 0)
        XCTAssertEqual(report.inspectedDocuments, 0)
        XCTAssertEqual(report.processedBytes, 0)
        XCTAssertTrue(report.hits.isEmpty)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertFalse(report.limited)
    }
}
