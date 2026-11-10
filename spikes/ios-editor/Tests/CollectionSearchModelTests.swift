import Foundation
import XCTest
@testable import MarkrightEditorSpike

private enum SearchModelTestError: Error, LocalizedError, Sendable {
    case failed
    var errorDescription: String? { "Injected search failure" }
}

/// Continuations deliberately ignore cancellation, like work already running on
/// the store actor. Each request can finish independently and out of order.
private actor ControlledCollectionSearch {
    struct Request: Sendable {
        let collection: String
        let query: String
    }
    private var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<CollectionSearchReport, any Error>] = [:]
    private var arrivals: [Int: [CheckedContinuation<Request, Never>]] = [:]

    func search(_ collection: String, _ query: String) async throws -> CollectionSearchReport {
        let index = requests.count
        let request = Request(collection: collection, query: query)
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            for waiter in arrivals.removeValue(forKey: index) ?? [] { waiter.resume(returning: request) }
        }
    }

    func request(_ index: Int) async -> Request {
        if requests.indices.contains(index) { return requests[index] }
        return await withCheckedContinuation { arrivals[index, default: []].append($0) }
    }

    func count() -> Int { requests.count }

    func succeed(_ index: Int, report: CollectionSearchReport) {
        pending.removeValue(forKey: index)?.resume(returning: report)
    }

    func fail(_ index: Int) {
        pending.removeValue(forKey: index)?.resume(throwing: SearchModelTestError.failed)
    }
}

@MainActor final class CollectionSearchModelTests: XCTestCase {
    private func make(_ harness: ControlledCollectionSearch) -> CollectionSearchModel {
        CollectionSearchModel { try await harness.search($0, $1) }
    }

    private func receipt(_ collection: String = "Notes", _ query: String = "needle") -> CollectionSearchReport {
        CollectionSearchReport(collection: collection, query: query, totalDocuments: 1,
                               inspectedDocuments: 1, searchedDocuments: 1, processedBytes: 12,
                               hits: [], issues: [], limitations: [])
    }

    private func waitUntil(_ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Search state did not settle", file: file, line: line)
    }

    private func allowStaleCompletion() async {
        // The injected work has returned, but the model task still needs its
        // turn on the main actor. The current request remains deliberately held.
        try? await Task.sleep(for: .milliseconds(20))
    }

    func testInputsDoNotSearchUntilExplicitRunAndCurrentReceiptIsPublished() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        await allowStaleCompletion()
        let before = await harness.count()
        XCTAssertEqual(before, 0)
        XCTAssertFalse(model.isSearching)
        model.run()
        XCTAssertTrue(model.isSearching)
        let request = await harness.request(0)
        XCTAssertEqual(request.collection, "Notes")
        XCTAssertEqual(request.query, "needle")
        await harness.succeed(0, report: receipt())
        await waitUntil { !model.isSearching }
        XCTAssertEqual(model.report?.collection, "Notes")
        XCTAssertEqual(model.report?.query, "needle")
        XCTAssertNil(model.errorMessage)
    }

    func testValidationRejectsMissingScopeEmptyAndOversizedQueriesWithoutIO() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.query = "needle"
        model.run()
        XCTAssertNotNil(model.errorMessage)
        model.setCollection("Notes")
        model.query = ""
        model.run()
        XCTAssertNotNil(model.errorMessage)
        // 129 supplementary scalars fit in 129 Characters but exceed 256 UTF-16 units.
        model.query = String(repeating: "😀", count: 129)
        model.run()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.report)
        let count = await harness.count()
        XCTAssertEqual(count, 0)
    }

    func testWhitespaceAndExactUTF16BoundaryAreValidQueries() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        for (index, query) in [" \t\n", String(repeating: "😀", count: 128)].enumerated() {
            model.query = query
            model.run()
            let request = await harness.request(index)
            XCTAssertTrue(request.query.utf8.elementsEqual(query.utf8))
            await harness.succeed(index, report: receipt("Notes", query))
            await waitUntil { !model.isSearching }
            XCTAssertNil(model.errorMessage)
            XCTAssertTrue(model.report?.query.utf8.elementsEqual(query.utf8) == true)
        }
    }

    func testNewQueryRejectsOldReportAfterNewerReceiptArrives() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "old"
        model.run()
        _ = await harness.request(0)
        model.query = "new"
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.report)
        model.run()
        _ = await harness.request(1)
        await harness.succeed(1, report: receipt("Notes", "new"))
        await waitUntil { !model.isSearching }
        await harness.succeed(0, report: receipt("Notes", "old"))
        await allowStaleCompletion()
        XCTAssertEqual(model.report?.query, "new")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
    }

    func testRerunningSameInputsRejectsOldErrorWithoutClearingNewBusy() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        model.run()
        _ = await harness.request(0)
        model.run()
        _ = await harness.request(1)
        await harness.fail(0)
        await allowStaleCompletion()
        XCTAssertTrue(model.isSearching)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.report)
        await harness.succeed(1, report: receipt())
        await waitUntil { !model.isSearching }
        XCTAssertEqual(model.report?.query, "needle")
    }

    func testScopeChangeRejectsOldReportWithoutClearingNewBusy() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        model.run()
        _ = await harness.request(0)
        model.setCollection("Other")
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.report)
        model.run()
        _ = await harness.request(1)
        await harness.succeed(0, report: receipt())
        await allowStaleCompletion()
        XCTAssertTrue(model.isSearching)
        XCTAssertNil(model.report)
        XCTAssertNil(model.errorMessage)
        await harness.succeed(1, report: receipt("Other"))
        await waitUntil { !model.isSearching }
        XCTAssertEqual(model.report?.collection, "Other")
    }

    func testByteDistinctCanonicalEquivalentQueryInvalidatesReceipt() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "é"
        model.run()
        _ = await harness.request(0)
        await harness.succeed(0, report: receipt("Notes", "é"))
        await waitUntil { !model.isSearching }
        model.query = "é"
        XCTAssertNotNil(model.report)
        model.setCollection("Notes")
        XCTAssertNotNil(model.report)
        model.query = "e\u{301}"
        XCTAssertNil(model.report)
        XCTAssertNil(model.errorMessage)
        let count = await harness.count()
        XCTAssertEqual(count, 1)
    }

    func testCurrentErrorPersistsUntilNewRunOrInputChangeAndRetryResetsIt() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        model.run()
        _ = await harness.request(0)
        await harness.fail(0)
        await waitUntil { !model.isSearching }
        XCTAssertEqual(model.errorMessage, "Injected search failure")
        model.cancel(clearResults: false)
        XCTAssertEqual(model.errorMessage, "Injected search failure")
        model.run()
        XCTAssertTrue(model.isSearching)
        XCTAssertNil(model.errorMessage)
        _ = await harness.request(1)
        await harness.succeed(1, report: receipt())
        await waitUntil { !model.isSearching }
        XCTAssertNotNil(model.report)
        model.cancel(clearResults: false)
        XCTAssertNotNil(model.report)
        model.query = "different"
        XCTAssertNil(model.report)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelAndNilCollectionInvalidateIgnoredCancellation() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        model.run()
        _ = await harness.request(0)
        model.cancel()
        XCTAssertFalse(model.isSearching)
        await harness.fail(0)
        await allowStaleCompletion()
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.report)
        model.run()
        _ = await harness.request(1)
        model.setCollection(nil)
        XCTAssertNil(model.collection)
        await harness.succeed(1, report: receipt())
        await allowStaleCompletion()
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.report)
        XCTAssertNil(model.errorMessage)
    }

    func testInFlightSearchDoesNotRetainModel() async {
        let harness = ControlledCollectionSearch()
        var model: CollectionSearchModel? = make(harness)
        weak var observed = model
        model?.setCollection("Notes")
        model?.query = "needle"
        model?.run()
        _ = await harness.request(0)
        model = nil
        XCTAssertNil(observed)
        observed = nil
        await harness.succeed(0, report: receipt())
    }

    func testCurrentReceiptMustMatchCapturedCollectionAndQueryBytes() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Café")
        model.query = "é"
        for (index, wrong) in [
            receipt("Other", "é"),
            receipt("Cafe\u{301}", "é"),
            receipt("Café", "e\u{301}")
        ].enumerated() {
            model.run()
            _ = await harness.request(index)
            await harness.succeed(index, report: wrong)
            await waitUntil { !model.isSearching }
            XCTAssertNil(model.report)
            XCTAssertNotNil(model.errorMessage)
        }
        model.run()
        XCTAssertNil(model.errorMessage)
        _ = await harness.request(3)
        await harness.succeed(3, report: receipt("Café", "é"))
        await waitUntil { !model.isSearching }
        XCTAssertNotNil(model.report)
        XCTAssertNil(model.errorMessage)
    }

    func testResultActionRequiresCurrentScopeQueryAndExactRefreshedHit() async {
        let harness = ControlledCollectionSearch()
        let model = make(harness)
        model.setCollection("Notes")
        model.query = "needle"
        let oldHit = CollectionSearchHit(name: "Café.mrk", matchCount: 1, moreMatches: false, preview: "old needle")
        var oldReport = receipt()
        oldReport.hits = [oldHit]
        model.run()
        _ = await harness.request(0)
        await harness.succeed(0, report: oldReport)
        await waitUntil { !model.isSearching }
        XCTAssertTrue(model.isCurrentResult(oldReport, hit: oldHit))

        model.query = "é"
        XCTAssertFalse(model.isCurrentResult(oldReport, hit: oldHit))
        let newHit = CollectionSearchHit(name: "Café.mrk", matchCount: 1, moreMatches: false, preview: "first é")
        var newReport = receipt("Notes", "é")
        newReport.hits = [newHit]
        model.run()
        _ = await harness.request(1)
        XCTAssertFalse(model.isCurrentResult(newReport, hit: newHit))
        await harness.succeed(1, report: newReport)
        await waitUntil { !model.isSearching }
        XCTAssertFalse(model.isCurrentResult(oldReport, hit: oldHit))
        XCTAssertTrue(model.isCurrentResult(newReport, hit: newHit))

        let refreshedHit = CollectionSearchHit(name: "Café.mrk", matchCount: 2, moreMatches: true, preview: "Café refreshed")
        var refreshedReport = receipt("Notes", "é")
        refreshedReport.hits = [refreshedHit]
        model.run()
        _ = await harness.request(2)
        await harness.succeed(2, report: refreshedReport)
        await waitUntil { !model.isSearching }
        XCTAssertFalse(model.isCurrentResult(newReport, hit: newHit))
        XCTAssertTrue(model.isCurrentResult(refreshedReport, hit: refreshedHit))
        for invented in [
            CollectionSearchHit(name: "invented.mrk", matchCount: 2, moreMatches: true, preview: "Café refreshed"),
            CollectionSearchHit(name: "Cafe\u{301}.mrk", matchCount: 2, moreMatches: true, preview: "Café refreshed"),
            CollectionSearchHit(name: "Café.mrk", matchCount: 2, moreMatches: true, preview: "Cafe\u{301} refreshed"),
            CollectionSearchHit(name: "Café.mrk", matchCount: 3, moreMatches: true, preview: "Café refreshed"),
            CollectionSearchHit(name: "Café.mrk", matchCount: 2, moreMatches: false, preview: "Café refreshed")
        ] {
            XCTAssertFalse(model.isCurrentResult(refreshedReport, hit: invented))
        }
        let wrongQuery = CollectionSearchReport(collection: refreshedReport.collection, query: "e\u{301}",
            totalDocuments: refreshedReport.totalDocuments, inspectedDocuments: refreshedReport.inspectedDocuments,
            searchedDocuments: refreshedReport.searchedDocuments, processedBytes: refreshedReport.processedBytes,
            hits: refreshedReport.hits, issues: refreshedReport.issues, limitations: refreshedReport.limitations)
        XCTAssertFalse(model.isCurrentResult(wrongQuery, hit: refreshedHit))
        model.setCollection("Other")
        XCTAssertFalse(model.isCurrentResult(refreshedReport, hit: refreshedHit))
    }
}
