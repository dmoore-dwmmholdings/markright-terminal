import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    // The SDK's .markdown constant starts at OS 27. Declare the established
    // identifier for our older deployment targets; this adds no data importer.
    static let markdownSourceCopy = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .utf8PlainText)
    static let markrightSourceCopy = UTType(exportedAs: "com.dwmm.markright.spike.source", conformingTo: .plainText)
}

/// An export-only adapter. There is no importer, path, editor reference, or
/// authority to adopt a new destination; every representation uses one snapshot.
struct SourceCopyTransfer: Transferable, Sendable {
    let snapshot: SourceCopySnapshot

    init(snapshot: SourceCopySnapshot) { self.snapshot = snapshot }

    var contentType: UTType { snapshot.format == .markdown ? .markdownSourceCopy : .markrightSourceCopy }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdownSourceCopy) { (item: SourceCopyTransfer) in
            item.snapshot.data
        }
        .exportingCondition { $0.snapshot.format == .markdown }
        .suggestedFileName { $0.snapshot.suggestedFilename }

        DataRepresentation(exportedContentType: .markrightSourceCopy) { (item: SourceCopyTransfer) in
            item.snapshot.data
        }
        .exportingCondition { $0.snapshot.format == .markright }
        .suggestedFileName { $0.snapshot.suggestedFilename }
    }
}
