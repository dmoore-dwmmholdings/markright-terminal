import Foundation
import Observation

enum SourceCopyFormat: Sendable, Equatable {
    case markdown
    case markright
}

enum SourceCopyExportError: Error, LocalizedError, Sendable, Equatable {
    case composing
    case changingDestination
    case invalidFilename
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .composing: "Finish typing before exporting a source copy."
        case .changingDestination: "Wait for the destination change before exporting a source copy."
        case .invalidFilename: "The document needs a valid .md or .mrk filename before exporting a source copy."
        case .tooLarge: "The source copy exceeds the 8 MiB export limit."
        }
    }
}

/// Immutable source bytes for a platform exporter. This is a separate copy, with
/// no reference to the editor or authority to complete the original's saves.
struct SourceCopySnapshot: Sendable, Identifiable {
    static let maximumBytes = 8 * 1024 * 1024
    let id: UUID
    let sessionID: UUID
    let sourceRevision: Int
    let suggestedFilename: String
    let format: SourceCopyFormat
    let data: Data

    @MainActor init(session: DocumentSession) throws {
        guard !session.model.composing else { throw SourceCopyExportError.composing }
        guard !session.isChangingDestination else { throw SourceCopyExportError.changingDestination }
        let name = session.document.name
        guard !name.isEmpty, name.utf8.count <= 255, !name.hasPrefix("."),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || $0 == "/" || $0 == "\\"
              }), let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            throw SourceCopyExportError.invalidFilename
        }
        let format: SourceCopyFormat
        switch name[name.index(after: dot)...].lowercased() {
        case "md": format = .markdown
        case "mrk": format = .markright
        default: throw SourceCopyExportError.invalidFilename
        }

        var bytes = Data()
        func append(_ source: String) throws {
            // Inspect at most the first excess byte, before encoding more. In
            // block mode this also avoids joining an oversized whole document.
            let remaining = Self.maximumBytes + 1 - bytes.count
            bytes.append(contentsOf: source.utf8.prefix(remaining))
            guard bytes.count <= Self.maximumBytes else { throw SourceCopyExportError.tooLarge }
        }
        if session.model.sourceMode {
            try append(session.model.documentSource)
        } else {
            for block in session.model.blocks {
                try append(block.source)
                try append(block.separatorAfter)
            }
        }
        id = UUID()
        sessionID = session.id
        sourceRevision = session.model.sourceRevision
        suggestedFilename = name
        self.format = format
        data = bytes
    }
}

@MainActor @Observable final class SourceCopyExportModel {
    private(set) var request: SourceCopySnapshot?
    private(set) var message: String?
    var isPending: Bool { request != nil }

    @discardableResult func begin(session: DocumentSession) -> Bool {
        guard request == nil else { return false }
        do {
            request = try SourceCopySnapshot(session: session)
            message = nil
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    @discardableResult func finish(id: UUID, result: Result<Void, any Error>) -> Bool {
        guard request?.id == id else { return false }
        request = nil
        switch result {
        case .success:
            message = "Source copy exported. You are still editing the original document."
        case .failure(let error):
            let cocoa = error as NSError
            if error is CancellationError || (cocoa.domain == NSCocoaErrorDomain && cocoa.code == CocoaError.Code.userCancelled.rawValue) {
                message = "Source copy export cancelled. You are still editing the original document."
            } else {
                message = "Source copy export was not confirmed. Check the destination before retrying."
            }
        }
        return true
    }

    @discardableResult func cancel(id: UUID) -> Bool {
        guard request?.id == id else { return false }
        request = nil
        message = "Source copy export cancelled. You are still editing the original document."
        return true
    }
}
