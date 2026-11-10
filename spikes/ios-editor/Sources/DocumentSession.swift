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
    private(set) var isChangingDestination = false
    private(set) var destinationError: String?
    private(set) var errorMessage: String?
    private(set) var recoveryDraft: RecoveryDraft?
    private(set) var recoveryRevision: Int?
    private(set) var recoveryCleanupPending = false
    private let recovery: DocumentRecovery?
    private var debouncer: Task<Void, Never>?
    private var pump: Task<Void, Never>?
    private var destinationTask: Task<StoredDocument?, Never>?
    private let save: @Sendable (StoredDocument, String) async throws -> StoredDocument

    init(document: StoredDocument, recovery: DocumentRecovery? = nil, save: @escaping @Sendable (StoredDocument, String) async throws -> StoredDocument) {
        self.document = document
        self.recovery = recovery
        model = EditorModel(source: document.source)
        self.save = save
    }
    var dirty: Bool { savedRevision != model.sourceRevision }
    var canClose: Bool { !dirty && !isSaving && !isChangingDestination && !model.composing && document.durabilityWarning == nil }
    var canKeepRecovery: Bool {
        recoveryDraft != nil && recoveryRevision == model.sourceRevision && !isSaving && !isChangingDestination && !model.composing
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
        if isChangingDestination { return "Saving new document…" }
        if let errorMessage { return errorMessage }
        if let warning = document.durabilityWarning { return warning }
        if model.composing { return "Finish typing to save" }
        if isSaving { return "Saving…" }
        return dirty ? "Unsaved changes" : "Saved on this device"
    }
    func scheduleSave() {
        debouncer?.cancel()
        debouncer = nil
        guard !isChangingDestination, !model.composing, dirty else { return }
        debouncer = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self else { return }
            await self.runSavePump()
        }
    }
    func flush() async -> Bool {
        debouncer?.cancel()
        debouncer = nil
        if let destinationTask { _ = await destinationTask.value }
        // A successful destination change may have scheduled newer edits while
        // this caller was waiting. This flush owns that work now.
        debouncer?.cancel()
        debouncer = nil
        guard !model.composing else { return false }
        await runSavePump()
        return canClose
    }
    func resumeAfterSaveAsDialog() {
        guard !isChangingDestination else { return }
        model.resumeEditorAfterDialog()
        // A failed copy keeps its sheet open for another name. Once that sheet
        // is cancelled/dismissed, normal autosave resumes on the retained file.
        scheduleSave()
    }
    func prepareSaveAsDialog() {
        guard !isChangingDestination else { return }
        destinationError = nil
    }
    func saveAs(collection: String, name: String,
                create: @escaping @Sendable (String, String, String) async throws -> StoredDocument) async -> StoredDocument? {
        guard !isChangingDestination else { return nil }
        guard !model.composing else {
            destinationError = "Finish typing to save a new document."
            return nil
        }
        isChangingDestination = true
        destinationError = nil
        debouncer?.cancel()
        debouncer = nil
        let task = Task {
            let receipt = await self.createDestination(collection: collection, name: name, create: create)
            self.isChangingDestination = false
            self.destinationTask = nil
            // Do not join a new pump here: flush may be awaiting this very task.
            if receipt != nil { self.scheduleSave() }
            return receipt
        }
        destinationTask = task
        return await task.value
    }
    private func createDestination(collection: String, name: String,
                                   create: @Sendable (String, String, String) async throws -> StoredDocument) async -> StoredDocument? {
        // An in-flight replacement owns its receipt. Let it finish before taking
        // the copy's checkpoint and baseline, but prevent another old-file write.
        if let pump { await pump.value }
        guard !model.composing else {
            destinationError = "Finish typing to save a new document."
            return nil
        }
        let revision = model.sourceRevision
        let source = model.source
        do {
            var checkpoint: RecoveryDraft?
            if let recovery {
                recoveryRevision = nil
                checkpoint = try await recovery.checkpoint(document, source)
                recoveryDraft = checkpoint
                recoveryRevision = revision
                recoveryCleanupPending = false
            }
            let receipt = try await create(collection, name, source)
            document = receipt
            savedRevision = revision
            errorMessage = nil
            // A warning still represents a committed new document. Keep its
            // checkpoint until an explicit confirmed save can retire it.
            if receipt.durabilityWarning == nil, let recovery, let checkpoint {
                recoveryRevision = nil
                recoveryCleanupPending = true
                do {
                    try await recovery.complete(checkpoint)
                    recoveryDraft = nil
                    recoveryCleanupPending = false
                } catch {
                    let message = "New document saved. Recovery cleanup could not be confirmed. \(error.localizedDescription)"
                    destinationError = message
                    errorMessage = message
                }
            }
            return receipt
        } catch {
            destinationError = "Could not save a new document. Your edits are still open. \(error.localizedDescription)"
            return nil
        }
    }
    private func runSavePump() async {
        if let pump { await pump.value; return }
        guard !isChangingDestination, !model.composing, dirty || document.durabilityWarning != nil || recoveryCleanupPending else { return }
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
        while !isChangingDestination && !model.composing && (dirty || document.durabilityWarning != nil || recoveryCleanupPending) {
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
