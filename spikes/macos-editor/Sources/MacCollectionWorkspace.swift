import AppKit
import Darwin
import Observation
import SwiftUI

@MainActor @Observable final class MacCollectionWorkspaceModel {
    let store: CollectionStore
    let sourceCopyExport = SourceCopyExportModel()
    var showsSourcePreview = false
    private(set) var collections: [String] = []
    private(set) var selectedCollection: String?
    private(set) var documents: [String] = []
    private(set) var recoveries: [RecoveryDraft] = []
    private(set) var recoveryIssues: [String] = []
    private(set) var interruptedWrites: [String] = []
    private(set) var session: DocumentSession?
    private(set) var lastCommittedDocument: StoredDocument?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var operationMessage: String?
    private(set) var hasNamingDialog = false
    private(set) var recoveryCloseRequested = false
    @ObservationIgnored private var closeDecision: CheckedContinuation<Bool, Never>?

    init(store: CollectionStore) { self.store = store }

    var status: String { session?.status ?? (isBusy ? "Working…" : "Choose a document or create a collection.") }
    var canCloseNow: Bool {
        !isBusy && !recoveryCloseRequested && !hasNamingDialog && !sourceCopyExport.isPending && (session?.canClose ?? true)
    }

    private func begin() -> Bool {
        guard !isBusy, !recoveryCloseRequested, !sourceCopyExport.isPending else { return false }
        guard session?.model.composing != true else {
            errorMessage = "Finish typing before changing the workspace."
            return false
        }
        isBusy = true
        errorMessage = nil
        return true
    }

    func refresh() async {
        guard begin() else { return }
        defer { isBusy = false }
        await refreshLists()
    }

    /// Refresh failures are independent from successful document receipts. Keep
    /// old lists and the adopted session available for an explicit retry.
    private func refreshLists() async {
        var failures: [String] = []
        do {
            let inventory = try await store.recoveries()
            recoveries = inventory.drafts
            recoveryIssues = inventory.issues
        } catch { failures.append("Recovery listing: \(error.localizedDescription)") }
        do { collections = try await store.collections() }
        catch { failures.append("Collection listing: \(error.localizedDescription)") }
        if let selectedCollection {
            do { documents = try await store.documents(in: selectedCollection) }
            catch { failures.append("Document listing: \(error.localizedDescription)") }
            do { interruptedWrites = try await store.interruptedWrites(in: selectedCollection) }
            catch { failures.append("Interrupted-write listing: \(error.localizedDescription)") }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    private func flushBeforeReplacingSession() async -> Bool {
        guard let session else { return true }
        guard await session.flush(), self.session === session, session.canClose else {
            errorMessage = "The current document is still open. \(session.status) Save a new copy or retry saving before switching."
            return false
        }
        return true
    }

    func selectCollection(_ name: String) async {
        guard !hasNamingDialog, begin() else { return }
        defer { isBusy = false }
        guard await flushBeforeReplacingSession() else { return }
        do {
            let listed = try await store.documents(in: name)
            var interrupted: [String] = []
            var listingWarning: String?
            do { interrupted = try await store.interruptedWrites(in: name) }
            catch { listingWarning = error.localizedDescription }
            guard await flushBeforeReplacingSession() else { return }
            selectedCollection = name
            documents = listed
            interruptedWrites = interrupted
            if session?.document.collection != name { session = nil }
            errorMessage = listingWarning
        } catch { errorMessage = error.localizedDescription }
    }

    func createCollection(_ name: String) async -> Bool {
        guard begin() else { return false }
        defer { isBusy = false }
        guard await flushBeforeReplacingSession() else { return false }
        do {
            try await store.createCollection(name)
            await finishCreatedCollection(name, warning: nil)
            return true
        } catch CollectionStoreError.collectionDurabilityUncertain(let createdName) {
            // mkdir committed even though synchronization was not acknowledged.
            await finishCreatedCollection(createdName, warning: CollectionStoreError.collectionDurabilityUncertain(createdName).localizedDescription)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func finishCreatedCollection(_ name: String, warning: String?) async {
        if !collections.contains(name) { collections.append(name) }
        operationMessage = warning ?? "Created collection \(name)."
        if await flushBeforeReplacingSession() {
            selectedCollection = name
            documents = []
            interruptedWrites = []
            session = nil
        } else {
            operationMessage = "\(operationMessage ?? "") The current document remains open with its newer edits."
        }
        await refreshLists()
    }

    @discardableResult func openDocument(_ name: String) async -> StoredDocument? {
        guard !hasNamingDialog, let selectedCollection, begin() else { return nil }
        defer { isBusy = false }
        guard await flushBeforeReplacingSession() else { return nil }
        do {
            let receipt = try await store.open(collection: selectedCollection, name: name)
            guard await flushBeforeReplacingSession() else { return nil }
            if let current = session, current.document.collection == receipt.collection, current.document.name == receipt.name {
                // A late edit may have advanced this very file while the open
                // was waiting. Keep its newer saved source and selection.
                return current.document
            }
            adopt(receipt)
            return receipt
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult func createDocument(name: String, source: String = "") async -> StoredDocument? {
        guard let selectedCollection, begin() else { return nil }
        defer { isBusy = false }
        guard await flushBeforeReplacingSession() else { return nil }
        do {
            let receipt = try await store.createDocument(collection: selectedCollection, name: name, source: source)
            retainCommittedReceipt(receipt)
            operationMessage = receipt.durabilityWarning ?? "Created \(receipt.name)."
            if await flushBeforeReplacingSession() {
                let message = operationMessage
                adopt(receipt)
                operationMessage = message
            } else {
                operationMessage = "\(operationMessage ?? "") The new file \(receipt.name) in \(receipt.collection) is retained; the current document remains open with its newer edits."
            }
            await refreshLists()
            return receipt
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult func restore(_ draft: RecoveryDraft, collection: String, name: String) async -> StoredDocument? {
        guard begin() else { return nil }
        defer { isBusy = false }
        guard await flushBeforeReplacingSession() else { return nil }
        do {
            let receipt = try await store.restoreRecovery(draft, collection: collection, name: name)
            // A cleanup/listing error must never offer to republish this copy.
            retainCommittedReceipt(receipt.document)
            operationMessage = [receipt.document.durabilityWarning, receipt.retirementWarning].compactMap { $0 }.joined(separator: "\n")
            if operationMessage?.isEmpty == true { operationMessage = "Restored a new copy as \(receipt.document.name)." }
            if await flushBeforeReplacingSession() {
                let message = operationMessage
                adopt(receipt.document)
                operationMessage = message
            } else {
                operationMessage = "\(operationMessage ?? "") The new file is retained in \(receipt.document.collection); the current document remains open with its newer edits."
            }
            await refreshLists()
            return receipt.document
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult func prepareSaveAsDialog() -> Bool {
        guard let session, !isBusy, !hasNamingDialog, !sourceCopyExport.isPending, !session.model.composing else { return false }
        session.prepareSaveAsDialog()
        hasNamingDialog = true
        return true
    }

    func resumeAfterSaveAsDialog() {
        hasNamingDialog = false
        session?.resumeAfterSaveAsDialog()
    }

    @discardableResult func beginSourceCopyExport() -> Bool {
        guard let session, !isBusy, !hasNamingDialog, !recoveryCloseRequested else { return false }
        return sourceCopyExport.begin(session: session)
    }

    @discardableResult func saveAs(collection: String, name: String) async -> StoredDocument? {
        guard let session, begin() else { return nil }
        defer { isBusy = false }
        let originalExtension = (session.document.name as NSString).pathExtension
        guard (name as NSString).pathExtension == originalExtension else {
            errorMessage = "Keep the original .\(originalExtension) extension for the new source copy."
            return nil
        }
        let store = store
        guard let receipt = await session.saveAs(collection: collection, name: name, create: { collection, name, source in
            try await store.createDocument(collection: collection, name: name, source: source)
        }) else {
            errorMessage = session.destinationError
            return nil
        }
        // The session itself owns this receipt, including newer in-flight edits.
        selectedCollection = receipt.collection
        documents = []
        interruptedWrites = []
        retainCommittedReceipt(receipt)
        operationMessage = session.destinationError ?? receipt.durabilityWarning ?? "Saved new document \(receipt.name)."
        await refreshLists()
        return receipt
    }

    private func retainCommittedReceipt(_ receipt: StoredDocument) {
        lastCommittedDocument = receipt
        if !collections.contains(receipt.collection) { collections.append(receipt.collection) }
        if selectedCollection == receipt.collection, !documents.contains(receipt.name) { documents.append(receipt.name) }
    }

    func retrySave() async {
        guard begin() else { return }
        defer { isBusy = false }
        if let session { _ = await session.flush() }
    }

    private func adopt(_ document: StoredDocument) {
        let store = store
        let recoveryID = UUID()
        let recovery = DocumentRecovery(checkpoint: { document, source in
            try await store.checkpoint(document, source: source, sessionID: recoveryID)
        }, complete: { draft in try await store.completeCheckpoint(draft) })
        let next = DocumentSession(document: document, recovery: recovery) { document, source in
            try await store.save(document, source: source)
        }
        next.model.showSource()
        if selectedCollection != document.collection {
            documents = []
            interruptedWrites = []
        }
        selectedCollection = document.collection
        if !documents.contains(document.name) { documents.append(document.name) }
        session = next
        operationMessage = document.durabilityWarning
    }

    func prepareToClose() async -> Bool {
        // Refuse concurrent requests rather than replacing a pending decision.
        guard !isBusy, !recoveryCloseRequested, !hasNamingDialog, !sourceCopyExport.isPending,
              session?.model.composing != true,
              session?.isChangingDestination != true else {
            errorMessage = "Finish typing or the active operation before closing."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        guard let session else { return true }
        if await session.flush(), self.session === session, session.canClose { return true }
        guard session.canKeepRecovery else {
            errorMessage = "The window remains open. \(session.status)"
            return false
        }
        recoveryCloseRequested = true
        return await withCheckedContinuation { closeDecision = $0 }
    }

    func resolveRecoveryClose(keepRecovery: Bool) {
        guard recoveryCloseRequested, let closeDecision else { return }
        // Recheck the actual current revision, not the earlier sheet state.
        let safe = keepRecovery && !sourceCopyExport.isPending && session?.prepareRecoveryClose() == true
        if safe, let current = session {
            if let draft = current.recoveryDraft {
                recoveries.removeAll { $0.fileName == draft.fileName }
                recoveries.append(draft)
            }
            // No checkpoint is retired. Detach this generation before the
            // continuation resumes, so reopening can restore from the inbox.
            session = nil
        }
        self.closeDecision = nil
        recoveryCloseRequested = false
        closeDecision.resume(returning: safe)
    }

    @discardableResult func releaseSafelyClosedSession() -> Bool {
        guard canCloseNow else { return false }
        session = nil
        return true
    }
}

@MainActor final class MacCollectionWorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let model: MacCollectionWorkspaceModel
    private(set) var isClosed = false
    private var closeInProgress = false
    private var closeAuthorized = false

    init(model: MacCollectionWorkspaceModel, allowsSourceCopyExportPresentation: Bool = true) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Markright collections · Native research"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: MacCollectionWorkspace(
            model: model, allowsSourceCopyExportPresentation: allowsSourceCopyExportPresentation))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAuthorized {
            if model.canCloseNow { return true }
            closeAuthorized = false
            return false
        }
        // Refuse this close at the time it is requested. Otherwise the queued
        // task could start after export completion and act on a stale close.
        guard !closeInProgress, !model.sourceCopyExport.isPending else { return false }
        closeInProgress = true
        Task { [weak self] in
            guard let self else { return }
            let safe = await model.prepareToClose()
            closeInProgress = false
            if safe && model.canCloseNow {
                closeAuthorized = true
                sender.performClose(nil)
            }
        }
        return false
    }

    func prepareToTerminate() async -> Bool {
        if isClosed { return model.canCloseNow }
        guard !closeInProgress else { return false }
        closeInProgress = true
        defer { closeInProgress = false }
        let safe = await model.prepareToClose()
        return safe && model.canCloseNow
    }

    func showWorkspace() {
        isClosed = false
        closeAuthorized = false
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Only a currently safe session may be detached on the actual close.
        // If an unexpected late update arrived, retain it for a later reopen.
        model.releaseSafelyClosedSession()
        isClosed = true
    }
}

@MainActor final class MacCollectionWorkspaceManager {
    static let shared = MacCollectionWorkspaceManager()
    private(set) var controller: MacCollectionWorkspaceWindowController?
    var canCloseNow: Bool { controller?.model.canCloseNow ?? true }
    var hasPendingSourceCopyExport: Bool { controller?.model.sourceCopyExport.isPending ?? false }

    init(controller: MacCollectionWorkspaceWindowController? = nil) { self.controller = controller }

    // No directory resolution, store access, or native windows at app launch.
    func openWorkspace() {
        if let controller {
            controller.showWorkspace()
            Task { await controller.model.refresh() }
            return
        }
        // Resolve the trusted OS parent physically, then append our own leaf.
        // Never resolve a caller-supplied store root or a collection symlink.
        let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let physical = parent.path.withCString({ realpath($0, nil) }) else {
            let alert = NSAlert()
            alert.messageText = "Cannot open collections"
            alert.informativeText = "The application support folder is unavailable (system error \(errno))."
            alert.runModal()
            return
        }
        let root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
            .appendingPathComponent("MarkrightCollectionsResearch", isDirectory: true)
        free(physical)
        let model = MacCollectionWorkspaceModel(store: CollectionStore(root: root))
        let next = MacCollectionWorkspaceWindowController(model: model)
        controller = next
        next.showWorkspace()
    }

    func prepareToTerminate() async -> Bool {
        guard let controller else { return true }
        return await controller.prepareToTerminate()
    }
}

@MainActor final class MarkrightMacApplicationDelegate: NSObject, NSApplicationDelegate {
    private var terminationPending = false
    private let workspaceManager: MacCollectionWorkspaceManager
    private let reply: @MainActor (NSApplication, Bool) -> Void

    override convenience init() {
        self.init(workspaceManager: .shared) { sender, safe in sender.reply(toApplicationShouldTerminate: safe) }
    }

    // The private probe injects its own manager and inert reply, so it never
    // opens the real collection root or replies to a real termination request.
    init(workspaceManager: MacCollectionWorkspaceManager,
         reply: @escaping @MainActor (NSApplication, Bool) -> Void) {
        self.workspaceManager = workspaceManager
        self.reply = reply
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Refuse at request time, before a queued task can observe a completed
        // export and unexpectedly act on this earlier quit attempt.
        guard !terminationPending, !workspaceManager.hasPendingSourceCopyExport else { return .terminateCancel }
        terminationPending = true
        Task {
            let safe = await workspaceManager.prepareToTerminate()
            terminationPending = false
            reply(sender, safe && workspaceManager.canCloseNow)
        }
        return .terminateLater
    }
}

private enum MacNamingPurpose: String, Identifiable {
    case collection, document, saveAs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .collection: "New collection"
        case .document: "New document"
        case .saveAs: "Save as new document"
        }
    }
}

struct MacCollectionWorkspace: View {
    @Bindable var model: MacCollectionWorkspaceModel
    var allowsSourceCopyExportPresentation = true
    @State private var naming: MacNamingPurpose?
    @State private var preview: RecoveryDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Native collection and recovery prototype").font(.headline)
                Text("App-owned files on this Mac · No sync. Optional partial preview supports inline formatting; tables and code fences remain source. Linked assets are not copied.")
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                Text(model.status).font(.body).accessibilityIdentifier("mac-document-status")
                if let message = model.operationMessage { Text(message).font(.body).textSelection(.enabled) }
                if let error = model.errorMessage { Text(error).font(.body).foregroundStyle(.red).textSelection(.enabled) }
                if let message = model.sourceCopyExport.message {
                    Text(message).font(.body).textSelection(.enabled).accessibilityIdentifier("source-copy-export-message")
                }
                if model.sourceCopyExport.isPending {
                    Text("Choose where to export the source copy. You are still editing the original document.").font(.body)
                }
            }.padding()
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 230, idealWidth: 290, maxWidth: 420)
                source.frame(minWidth: 320)
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .toolbar {
            Button("New collection") { naming = .collection }.disabled(model.isBusy || model.sourceCopyExport.isPending || model.session?.model.composing == true)
            Button("New document") { naming = .document }.disabled(model.isBusy || model.sourceCopyExport.isPending || model.selectedCollection == nil || model.session?.model.composing == true)
            Button("Save as…") { if model.prepareSaveAsDialog() { naming = .saveAs } }
                .disabled(model.isBusy || model.sourceCopyExport.isPending || model.session == nil || model.session?.model.composing == true)
            Button("Export source copy…") { model.beginSourceCopyExport() }
                .accessibilityIdentifier("export-source-copy")
                .disabled(model.isBusy || model.hasNamingDialog || model.recoveryCloseRequested || model.sourceCopyExport.isPending ||
                          model.session == nil || model.session?.model.composing == true || model.session?.isChangingDestination == true)
            Toggle("Live preview", isOn: $model.showsSourcePreview)
                .accessibilityIdentifier("live-preview-toggle")
                .disabled(model.session == nil || model.isBusy || model.hasNamingDialog || model.recoveryCloseRequested ||
                          model.sourceCopyExport.isPending || model.session?.model.composing == true)
            Button("Refresh") { Task { await model.refresh() } }.disabled(model.isBusy || model.sourceCopyExport.isPending)
        }
        .background {
            if allowsSourceCopyExportPresentation, let request = model.sourceCopyExport.request {
                SourceCopyExporter(request: request, model: model.sourceCopyExport).id(request.id)
            }
        }
        .task { await model.refresh() }
        .sheet(item: $naming, onDismiss: { model.resumeAfterSaveAsDialog() }) { purpose in
            MacNamingSheet(model: model, purpose: purpose) { naming = nil }
        }
        .sheet(item: $preview) { draft in
            MacRecoverySheet(model: model, draft: draft) { preview = nil }
        }
        .confirmationDialog("Keep the current recovery copy and close?", isPresented: Binding(
            get: { model.recoveryCloseRequested },
            set: { if !$0 { model.resolveRecoveryClose(keepRecovery: false) } }
        ), titleVisibility: .visible) {
            Button("Close with current recovery copy") { model.resolveRecoveryClose(keepRecovery: true) }
            Button("Keep window open", role: .cancel) { model.resolveRecoveryClose(keepRecovery: false) }
        } message: {
            Text("Saving the document could not be confirmed. The acknowledged recovery copy contains the current source and can be restored as a new document from the recovery inbox.")
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collections").font(.headline)
                if model.collections.isEmpty { Text("Create a collection to begin.") }
                ForEach(model.collections, id: \.self) { name in
                    Button { Task { await model.selectCollection(name) } } label: {
                        HStack {
                            Text(name).lineLimit(nil)
                            if model.selectedCollection == name { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityValue(model.selectedCollection == name ? "Selected" : "")
                }
                if let collection = model.selectedCollection {
                    Divider()
                    Text("Documents in \(collection)").font(.headline)
                    if model.documents.isEmpty { Text("No listed documents.") }
                    ForEach(model.documents, id: \.self) { name in
                        let isOpen = model.session?.document.collection == collection && model.session?.document.name == name
                        Button { Task { await model.openDocument(name) } } label: {
                            HStack {
                                Text(verbatim: name)
                                if isOpen { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityValue(isOpen ? "Open" : "")
                    }
                    CollectionSearchPanel(store: model.store, collection: collection) { name in
                        let scope = collection
                        Task {
                            guard model.selectedCollection == scope else { return }
                            await model.openDocument(name)
                        }
                    }.id(collection)
                }
                Divider()
                Text("Recovery inbox").font(.headline)
                if model.recoveries.isEmpty { Text("No listed recovery drafts.") }
                ForEach(model.recoveries, id: \.fileName) { draft in
                    Button("\(draft.name) in \(draft.collection)") { preview = draft }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(model.recoveryIssues.enumerated()), id: \.offset) { _, issue in
                    Text(issue).textSelection(.enabled)
                }
                if !model.interruptedWrites.isEmpty {
                    Text("Interrupted storage files are preserved. They have not been opened, applied, or removed.")
                }
            }.font(.body).buttonStyle(.borderless).padding()
                .fixedSize(horizontal: false, vertical: true)
        }.disabled(model.isBusy || model.sourceCopyExport.isPending || model.session?.model.composing == true)
    }

    @ViewBuilder private var source: some View {
        if let session = model.session {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.document.name).font(.headline).textSelection(.enabled)
                    if let recoveryStatus = session.recoveryStatus { Text(recoveryStatus).font(.body) }
                    if session.errorMessage != nil || session.document.durabilityWarning != nil {
                        Button("Retry save") { Task { await model.retrySave() } }.disabled(model.isBusy)
                    }
                }.padding([.horizontal, .top])
                // Captured generation rejects callbacks from a departing editor.
                let generation = session.model.editingGeneration
                HSplitView {
                    MacSourceEditor(value: session.model.documentSource, selection: session.model.documentSelection,
                                    isEditable: !model.isBusy && !model.hasNamingDialog) { value, composing, selection in
                        guard model.session?.id == session.id else { return }
                        session.model.updateDocumentSource(value, composing: composing, generation: generation, selection: selection)
                        session.scheduleSave()
                    }.id("\(session.id)-\(generation)").frame(minWidth: 160)
                    if model.showsSourcePreview {
                        SourcePreviewPanel(source: session.model.documentSource, selection: session.model.documentSelection,
                                           composing: session.model.composing)
                            .frame(minWidth: 180)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your source, stored locally").font(.title2)
                Text("Open a document from a collection, or create a new .mrk or .md source file. Recovery previews are inert plain text; restoring always creates a new copy.")
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MacNamingSheet: View {
    @Bindable var model: MacCollectionWorkspaceModel
    let purpose: MacNamingPurpose
    let dismiss: () -> Void
    @State private var name = ""
    @State private var collection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(purpose.title).font(.headline)
            Text(purpose == .collection ? "Use a visible folder name." : "Enter the complete filename, including .mrk or .md. Existing files are never overwritten.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            if purpose == .saveAs {
                Picker("Collection", selection: $collection) {
                    ForEach(model.collections, id: \.self) { Text($0).tag($0) }
                }
                Text("Keep the source document’s original extension. Linked assets are not copied.").font(.body)
            }
            TextField(purpose == .collection ? "Collection name" : "Filename", text: $name)
                .textFieldStyle(.roundedBorder)
            if let error = model.errorMessage { Text(error).font(.body).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel", role: .cancel, action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button(purpose == .saveAs ? "Save new copy" : "Create") {
                    Task {
                        let success: Bool
                        switch purpose {
                        case .collection: success = await model.createCollection(name)
                        case .document: success = await model.createDocument(name: name) != nil
                        case .saveAs: success = await model.saveAs(collection: collection, name: name) != nil
                        }
                        if success { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || (purpose == .saveAs && collection.isEmpty))
            }
        }.padding(24).frame(minWidth: 420, idealWidth: 520)
            .disabled(model.isBusy).interactiveDismissDisabled(model.isBusy)
            .onAppear {
                collection = model.session?.document.collection ?? model.selectedCollection ?? model.collections.first ?? ""
                if purpose == .saveAs, let document = model.session?.document {
                    let stem = (document.name as NSString).deletingPathExtension
                    name = stem + " copy." + (document.name as NSString).pathExtension
                } else if purpose == .document { name = "Untitled.mrk" }
            }
    }
}

private struct MacRecoverySheet: View {
    @Bindable var model: MacCollectionWorkspaceModel
    let draft: RecoveryDraft
    let dismiss: () -> Void
    @State private var collection = ""
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recovery preview · \(draft.name)").font(.headline)
            Text("Inert source from \(draft.collection). Restore publishes a new copy; it never replaces the original document. Linked assets are not copied.")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            MacSourceEditor(value: draft.source, selection: SourceSelection.beginning, isEditable: false,
                            accessibilityLabel: "Recovery source preview, read only") { _, _, _ in }
                .frame(minHeight: 220)
            Picker("Destination collection", selection: $collection) {
                ForEach(model.collections, id: \.self) { Text($0).tag($0) }
            }
            TextField("New filename, including extension", text: $name).textFieldStyle(.roundedBorder)
            if model.collections.isEmpty { Text("Create a collection in the workspace before restoring.").font(.body) }
            if let error = model.errorMessage { Text(error).font(.body).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Close", role: .cancel, action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Restore new copy") {
                    Task {
                        if await model.restore(draft, collection: collection, name: name) != nil { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).disabled(collection.isEmpty || name.isEmpty)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 760, minHeight: 480)
            .disabled(model.isBusy).interactiveDismissDisabled(model.isBusy)
            .onAppear {
                collection = model.collections.contains(draft.collection) ? draft.collection : model.collections.first ?? ""
                name = (draft.name as NSString).deletingPathExtension + " recovered." + (draft.name as NSString).pathExtension
            }
    }
}
