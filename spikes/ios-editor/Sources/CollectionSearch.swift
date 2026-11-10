import Foundation

struct CollectionSearchLimits: Sendable {
    let maxDocuments: Int
    let maxBytes: Int
    let maxResults: Int
    let maxMatchesPerDocument: Int

    init(maxDocuments: Int = 64, maxBytes: Int = 8 * 1_048_576,
         maxResults: Int = 50, maxMatchesPerDocument: Int = 100) {
        self.maxDocuments = min(max(maxDocuments, 0), 64)
        self.maxBytes = min(max(maxBytes, 0), 8 * 1_048_576)
        self.maxResults = min(max(maxResults, 0), 50)
        self.maxMatchesPerDocument = min(max(maxMatchesPerDocument, 0), 100)
    }
}

struct CollectionSearchHit: Sendable, Identifiable {
    let name: String
    let matchCount: Int
    let moreMatches: Bool
    let preview: String
    var id: String { name }
}

struct CollectionSearchReport: Sendable {
    let collection: String
    let query: String
    let totalDocuments: Int
    var inspectedDocuments: Int
    var searchedDocuments: Int
    /// Successful bytes plus conservative full-document reservations for failed reads.
    var processedBytes: Int
    var hits: [CollectionSearchHit]
    var issues: [String]
    var limitations: [String]
    var limited: Bool { !limitations.isEmpty }
}

enum CollectionSearchQueryError: Error, LocalizedError, Sendable, Equatable {
    case empty
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty: "Enter a saved-source search query."
        case .tooLong: "The search query is too long. Use a shorter phrase."
        }
    }
}

extension CollectionStore {
    /// An explicit, bounded read of saved app-owned documents. Enumeration and
    /// individual opens are separate snapshots, not an atomic external-file CAS.
    /// Failures consume a full document reservation because bytes read are unknown.
    func searchSavedSource(in collection: String, query: String,
                           limits: CollectionSearchLimits = .init()) async throws -> CollectionSearchReport {
        guard !query.isEmpty else { throw CollectionSearchQueryError.empty }
        guard query.utf16.prefix(257).count <= 256 else { throw CollectionSearchQueryError.tooLong }
        try Task.checkCancellation()
        let names = try documents(in: collection, createRootIfMissing: false)
        var report = CollectionSearchReport(collection: collection, query: query, totalDocuments: names.count,
                                            inspectedDocuments: 0, searchedDocuments: 0, processedBytes: 0,
                                            hits: [], issues: [], limitations: [])
        guard limits.maxMatchesPerDocument > 0 else {
            report.limitations.append("The per-document match limit is zero; saved document source was not read.")
            try Task.checkCancellation()
            return report
        }
        for (index, name) in names.enumerated() {
            try Task.checkCancellation()
            var stop = false
            if report.inspectedDocuments >= limits.maxDocuments {
                report.limitations.append("The document limit (\(limits.maxDocuments)) stopped the search before every saved document was inspected.")
                stop = true
            }
            if limits.maxBytes - report.processedBytes < Self.maximumDocumentBytes {
                report.limitations.append("The byte budget (\(limits.maxBytes)) cannot reserve another 1 MiB document read; saved documents remain unsearched.")
                stop = true
            }
            if report.hits.count >= limits.maxResults {
                report.limitations.append("The result file limit (\(limits.maxResults)) stopped the search; additional matching files may exist.")
                stop = true
            }
            if stop { break }
            report.inspectedDocuments += 1
            do {
                let document = try open(collection: collection, name: name, createRootIfMissing: false)
                report.processedBytes += document.baseline.count
                report.searchedDocuments += 1
                if let hit = try savedSourceHit(document, query: query, maximumMatches: limits.maxMatchesPerDocument) {
                    report.hits.append(hit)
                    if hit.moreMatches, !report.limitations.contains(where: { $0.hasPrefix("The per-document match limit") }) {
                        report.limitations.append("The per-document match limit (\(limits.maxMatchesPerDocument)) omitted additional matches in one or more files.")
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.processedBytes += Self.maximumDocumentBytes
                report.issues.append("\(name): \(error.localizedDescription) The failed read used a 1 MiB budget reservation.")
            }
            if index + 1 < names.count {
                await Task.yield()
            }
        }
        try Task.checkCancellation()
        return report
    }

    private func savedSourceHit(_ document: StoredDocument, query: String, maximumMatches: Int) throws -> CollectionSearchHit? {
        let source = document.source as NSString
        let locale = Locale(identifier: "en_US_POSIX")
        var cursor = 0
        var count = 0
        var first: NSRange?
        var more = false
        while cursor < source.length {
            try Task.checkCancellation()
            // Without .literal, NSString preserves canonical Unicode equivalence.
            // The query is plain text: no regular-expression option is enabled.
            let match = source.range(of: query, options: [.caseInsensitive],
                                     range: NSRange(location: cursor, length: source.length - cursor), locale: locale)
            guard match.location != NSNotFound, match.length > 0 else { break }
            if first == nil { first = match }
            if count == maximumMatches {
                more = true
                break
            }
            count += 1
            cursor = match.location + max(match.length, 1)
        }
        guard let first else { return nil }
        return CollectionSearchHit(name: document.name, matchCount: count, moreMatches: more,
                                   preview: savedSourcePreview(source, startingAt: first.location))
    }

    /// Plain source beginning at the first match; never decoded as Markdown or
    /// followed as a URL. Preserve paired UTF-16 surrogates and CRLF boundaries.
    private func savedSourcePreview(_ source: NSString, startingAt location: Int) -> String {
        var start = location
        if start > 0 {
            let unit = source.character(at: start)
            if (0xDC00...0xDFFF).contains(unit) || (unit == 0x0A && source.character(at: start - 1) == 0x0D) {
                start -= 1
            }
        }
        var end = min(source.length, start + 160)
        if end < source.length, end > start {
            let previous = source.character(at: end - 1)
            if (0xD800...0xDBFF).contains(previous) || (previous == 0x0D && source.character(at: end) == 0x0A) {
                end -= 1
            }
        }
        let excerpt = source.substring(with: NSRange(location: start, length: end - start))
        return excerpt + (end < source.length ? "…" : "")
    }
}
