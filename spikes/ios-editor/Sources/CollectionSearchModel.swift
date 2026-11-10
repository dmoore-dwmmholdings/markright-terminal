import Foundation
import Observation

/// State for an explicit search of saved source. Editing and navigation remain
/// owned by the caller; changing either input only invalidates this search.
@MainActor @Observable final class CollectionSearchModel {
    var query = "" {
        didSet {
            if !query.utf8.elementsEqual(oldValue.utf8) { cancel() }
        }
    }
    private(set) var collection: String?
    private(set) var report: CollectionSearchReport?
    private(set) var errorMessage: String?
    private(set) var isSearching = false
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    private let search: @Sendable (String, String) async throws -> CollectionSearchReport

    init(search: @escaping @Sendable (String, String) async throws -> CollectionSearchReport) {
        self.search = search
    }

    convenience init(store: CollectionStore) {
        self.init { collection, query in
            try await store.searchSavedSource(in: collection, query: query)
        }
    }

    func setCollection(_ name: String?) {
        let unchanged: Bool
        switch (collection, name) {
        case (nil, nil): unchanged = true
        case let (current?, next?): unchanged = current.utf8.elementsEqual(next.utf8)
        default: unchanged = false
        }
        guard !unchanged else { return }
        collection = name
        cancel()
    }

    func run() {
        cancel()
        guard let collection else {
            errorMessage = "Choose a collection to search."
            return
        }
        guard !query.isEmpty else {
            errorMessage = "Enter a search query."
            return
        }
        guard query.utf16.prefix(257).count <= 256 else {
            errorMessage = "The search query is too long. Use a shorter phrase."
            return
        }

        let query = query
        let search = search
        let id = requestID
        isSearching = true
        // Do not promote self before awaiting: even a search that ignores
        // cancellation must not keep the panel's model alive.
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let report = try await search(collection, query)
                guard let self, self.requestID == id else { return }
                guard report.collection.utf8.elementsEqual(collection.utf8),
                      report.query.utf8.elementsEqual(query.utf8) else {
                    self.errorMessage = "Search returned results for different inputs. Run the search again."
                    self.isSearching = false
                    self.task = nil
                    return
                }
                self.report = report
                self.errorMessage = nil
                self.isSearching = false
                self.task = nil
            } catch {
                guard let self, self.requestID == id else { return }
                self.errorMessage = error.localizedDescription
                self.isSearching = false
                self.task = nil
            }
        }
    }

    func cancel(clearResults: Bool = true) {
        requestID = UUID()
        task?.cancel()
        task = nil
        isSearching = false
        if clearResults {
            report = nil
            errorMessage = nil
        }
    }

    /// A rendered action may outlive the report that created it. Revalidate its
    /// scope, query and exact hit against current state before the caller opens it.
    func isCurrentResult(_ captured: CollectionSearchReport, hit: CollectionSearchHit) -> Bool {
        guard !isSearching, let current = report, let collection,
              current.collection.utf8.elementsEqual(collection.utf8),
              captured.collection.utf8.elementsEqual(collection.utf8),
              current.query.utf8.elementsEqual(query.utf8),
              captured.query.utf8.elementsEqual(query.utf8) else { return false }
        func matches(_ candidate: CollectionSearchHit) -> Bool {
            candidate.name.utf8.elementsEqual(hit.name.utf8)
                && candidate.preview.utf8.elementsEqual(hit.preview.utf8)
                && candidate.matchCount == hit.matchCount
                && candidate.moreMatches == hit.moreMatches
        }
        return captured.hits.contains(where: matches) && current.hits.contains(where: matches)
    }
}
