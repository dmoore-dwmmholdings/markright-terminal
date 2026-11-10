import Foundation

/// Inert, app-owned recovery bytes. `id` identifies a checkpoint version;
/// `fileName` identifies the candidate, including an interrupted pending write.
struct RecoveryDraft: Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let fileName: String
    let collection: String
    let name: String
    let source: String
    let baseline: Data

    init(id: UUID = UUID(), sessionID: UUID, fileName: String? = nil,
         collection: String, name: String, source: String, baseline: Data) {
        self.id = id
        self.sessionID = sessionID
        self.fileName = fileName ?? sessionID.uuidString + ".draft"
        self.collection = collection
        self.name = name
        self.source = source
        self.baseline = baseline
    }
}

struct RecoveryInventory: Sendable {
    let drafts: [RecoveryDraft]
    let issues: [String]
}

struct RecoveryRestoreReceipt: Sendable {
    let document: StoredDocument
    let retirementWarning: String?
}
