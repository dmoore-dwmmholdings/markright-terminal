import SwiftUI

struct DocumentRecovery: Sendable {
    let checkpoint: @Sendable (StoredDocument, String) async throws -> RecoveryDraft
    let complete: @Sendable (RecoveryDraft) async throws -> Void
}

/// One save pump per open document. A completed receipt always advances the
/// baseline, including when newer text arrived during the write.
@MainActor @Observable final class DocumentSession: Identifiable {
    let id = UUID()
    let model: EditorModel
    private(set) var document: StoredDocument
    private(set) var savedRevision = 0
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var recoveryDraft: RecoveryDraft?
    private(set) var recoveryRevision: Int?
    private(set) var recoveryCleanupPending = false
    private let recovery: DocumentRecovery?
    private var debouncer: Task<Void, Never>?
    private var pump: Task<Void, Never>?
    private let save: @Sendable (StoredDocument, String) async throws -> StoredDocument

    init(document: StoredDocument, recovery: DocumentRecovery? = nil, save: @escaping @Sendable (StoredDocument, String) async throws -> StoredDocument) {
        self.document = document
        self.recovery = recovery
        model = EditorModel(source: document.source)
        self.save = save
    }
    var dirty: Bool { savedRevision != model.sourceRevision }
    var canClose: Bool { !dirty && !isSaving && !model.composing && document.durabilityWarning == nil }
    var canKeepRecovery: Bool {
        recoveryDraft != nil && recoveryRevision == model.sourceRevision && !isSaving && !model.composing
    }
    var recoveryStatus: String? {
        guard recovery != nil else { return nil }
        if recoveryDraft != nil && recoveryRevision == model.sourceRevision { return "Recovery copy saved on this device" }
        return dirty ? "Newest edits do not yet have a confirmed recovery copy" : nil
    }
    func prepareRecoveryClose() -> Bool {
        guard canKeepRecovery else { return false }
        debouncer?.cancel()
        debouncer = nil
        return true
    }
    var status: String {
        if let errorMessage { return errorMessage }
        if let warning = document.durabilityWarning { return warning }
        if model.composing { return "Finish typing to save" }
        if isSaving { return "Saving…" }
        return dirty ? "Unsaved changes" : "Saved on this device"
    }
    func scheduleSave() {
        debouncer?.cancel()
        guard !model.composing, dirty else { return }
        debouncer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self else { return }
            await self.runSavePump()
        }
    }
    func flush() async -> Bool {
        debouncer?.cancel()
        debouncer = nil
        guard !model.composing else { return false }
        await runSavePump()
        return canClose
    }
    private func runSavePump() async {
        if let pump { await pump.value; return }
        guard !model.composing, dirty || document.durabilityWarning != nil || recoveryCleanupPending else { return }
        let task = Task {
            await self.saveUntilCurrent()
            self.pump = nil
        }
        pump = task
        await task.value
    }
    private func saveUntilCurrent() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        while !model.composing && (dirty || document.durabilityWarning != nil || recoveryCleanupPending) {
            let revision = model.sourceRevision
            let source = model.source
            do {
                var checkpoint: RecoveryDraft?
                if let recovery {
                    // A failed or uncertain replacement cannot inherit an older
                    // checkpoint acknowledgement, even when text is unchanged.
                    recoveryRevision = nil
                    checkpoint = try await recovery.checkpoint(document, source)
                    recoveryDraft = checkpoint
                    recoveryRevision = revision
                }
                document = try await save(document, source)
                savedRevision = revision
                // A committed write with uncertain durability is not retried in
                // a tight loop. Keep it visible and require an explicit retry.
                if document.durabilityWarning != nil { return }
                if let recovery, let checkpoint {
                    // Retirement may unlink before reporting an fsync error. Do
                    // not advertise an extant recovery copy after that point.
                    recoveryRevision = nil
                    recoveryCleanupPending = true
                    do {
                        try await recovery.complete(checkpoint)
                        recoveryDraft = nil
                        recoveryCleanupPending = false
                    } catch {
                        errorMessage = "Document saved. Recovery cleanup could not be confirmed. \(error.localizedDescription)"
                        return
                    }
                }
            } catch {
                if !dirty && document.durabilityWarning == nil {
                    errorMessage = "Document saved. Recovery cleanup could not be confirmed. \(error.localizedDescription)"
                } else {
                    errorMessage = "Could not save. Your edits are still open. \(error.localizedDescription)"
                }
                return
            }
        }
    }
}
