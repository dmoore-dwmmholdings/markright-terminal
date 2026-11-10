import SwiftUI

struct CollectionLibrary: View {
    let store: CollectionStore
    @State private var collections: [String] = []
    @State private var collection: String?
    @State private var documents: [String] = []
    @State private var session: DocumentSession?
    @State private var recoverySelection: RecoveryDraft?
    @State private var recoveryDrafts: [RecoveryDraft] = []
    @State private var recoveryIssues: [String] = []
    @State private var interruptedWrites: [String] = []
    @State private var errorMessage: String?
    @State private var name = ""
    @State private var newCollection = false
    @State private var newDocument = false
    @State private var busy = false
    @Environment(\.scenePhase) private var scenePhase

    static var testRootID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--library-test-root"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]) else { return nil }
        return id.uuidString
    }
    static var rootURL: URL {
        let documents = URL.documentsDirectory.resolvingSymlinksInPath()
        if let testRootID { return documents.appendingPathComponent("MarkrightTest-\(testRootID)", isDirectory: true) }
        return documents.appendingPathComponent("MarkrightCollections", isDirectory: true)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                // Keep short lists mounted across Dynamic Type relayout. Larger
                // lists remain lazy; these bounds never truncate stored entries.
                if collections.count + documents.count + recoveryDrafts.count <= 128 {
                    VStack(alignment: .leading, spacing: 16) { libraryRows }.padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) { libraryRows }.padding()
                }
            }
            .navigationTitle("Markright")
            .disabled(busy)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading) {
                    Button("New collection") { name = ""; newCollection = true }.accessibilityIdentifier("new-collection")
                    if collection != nil {
                        Button("New document") { name = ""; newDocument = true }.accessibilityIdentifier("new-document")
                    }
                    if errorMessage != nil { Button("Refresh") { perform { try await refresh() } } }
                }
                .font(.body).buttonStyle(.borderedProminent).controlSize(.large)
                .tint(Color(red: 0.35, green: 0.25, blue: 0.05))
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(Color(uiColor: .systemBackground)).disabled(busy)
            }
            .alert("New collection", isPresented: $newCollection) {
                TextField("Collection name", text: $name)
                Button("Create") { let value = name; perform { try await store.createCollection(value); try await refresh(); try await select(value) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New document", isPresented: $newDocument) {
                TextField("Document name", text: $name)
                Button("Create") {
                    let value = name
                    guard let collection else { return }
                    perform {
                        let filename = value + ".mrk"
                        let document = try await store.createDocument(collection: collection, name: filename)
                        // Preserve the creation receipt even if a later list
                        // refresh fails; the editor opens the committed file.
                        documents = []
                        interruptedWrites = []
                        session = makeSession(document)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a name without a file extension.") }
        }
        .task { perform { try await refresh() } }
        .sheet(item: $session, onDismiss: { perform { try await refresh() } }) { session in
            DocumentWorkspace(session: session, collections: collections, create: { collection, name, source in
                try await store.createDocument(collection: collection, name: name, source: source)
            }) {
                collection = session.document.collection
                self.session = nil
            }
        }
        .sheet(item: $recoverySelection, onDismiss: { perform { try await refresh() } }) { draft in
            RecoveryWorkspace(draft: draft, collections: collections, restore: { target, name in
                let receipt = try await store.restoreRecovery(draft, collection: target, name: name)
                // Publishing succeeded. A later listing failure must never
                // discard this receipt or invite duplicate restoration.
                collection = target
                documents = []
                interruptedWrites = []
                return receipt
            }) { recoverySelection = nil }.id(draft.fileName + draft.id.uuidString)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, let session { Task { _ = await session.flush() } }
        }
    }
    @ViewBuilder private var libraryRows: some View {
        if !recoveryDrafts.isEmpty {
            Section {
                ForEach(recoveryDrafts, id: \.fileName) { draft in
                    Button("\(draft.name) in \(draft.collection)") { recoverySelection = draft }
                        .buttonStyle(.plain).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("recovery-\(draft.name)")
                }
            } header: { Text("Recovered edits").font(.headline) }
        }
        ForEach(Array(recoveryIssues.enumerated()), id: \.offset) { _, issue in
            Text(issue).fixedSize(horizontal: false, vertical: true)
        }
        Section {
            if collections.isEmpty { Text("Create a collection to start writing.") }
            ForEach(collections, id: \.self) { item in
                Button { perform { try await select(item) } } label: {
                    HStack {
                        Text(item)
                        Spacer()
                        if collection == item { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityValue(collection == item ? "Selected" : "")
                .accessibilityIdentifier("collection-\(item)")
            }
        } header: { Text("Collections").font(.headline).foregroundStyle(.primary) }
        if let collection {
            Section {
                if documents.isEmpty { Text("No documents yet.") }
                ForEach(documents, id: \.self) { item in
                    Button(item) { perform { try await open(collection: collection, name: item) } }
                        .buttonStyle(.plain).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).accessibilityIdentifier("document-\(item)")
                }
            } header: { Text("Documents in \(collection)").font(.headline).foregroundStyle(.primary) }
        }
        if !interruptedWrites.isEmpty {
            Text("Interrupted storage files are preserved in this collection. They have not been applied or removed.")
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("interrupted-writes-notice")
        }
        Section {
            Text("Stored on this device. No sync.").font(.body).fixedSize(horizontal: false, vertical: true)
            Text("Collection and editing prototype.").font(.body).fixedSize(horizontal: false, vertical: true)
            if let errorMessage { Text(errorMessage).accessibilityIdentifier("library-error") }
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await operation(); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func refresh() async throws {
        // Recovery is read first, so valid checkpoints remain visible even when
        // another collection entry prevents ordinary browsing.
        let inventory = try await store.recoveries()
        recoveryDrafts = inventory.drafts
        recoveryIssues = inventory.issues
        collections = try await store.collections()
        if let collection, collections.contains(collection) {
            documents = try await store.documents(in: collection)
            interruptedWrites = try await store.interruptedWrites(in: collection)
        } else { collection = nil; documents = []; interruptedWrites = [] }
    }
    private func select(_ name: String) async throws {
        let listed = try await store.documents(in: name)
        let interrupted = try await store.interruptedWrites(in: name)
        collection = name
        documents = listed
        interruptedWrites = interrupted
    }
    private func open(collection: String, name: String) async throws {
        session = makeSession(try await store.open(collection: collection, name: name))
    }
    private func makeSession(_ document: StoredDocument) -> DocumentSession {
        let failSaves = Self.testRootID != nil && ProcessInfo.processInfo.arguments.contains("--fail-library-save")
        let recoveryID = UUID()
        let recovery = DocumentRecovery(checkpoint: { document, source in
            try await store.checkpoint(document, source: source, sessionID: recoveryID)
        }, complete: { draft in try await store.completeCheckpoint(draft) })
        return DocumentSession(document: document, recovery: recovery) { document, source in
            if failSaves { throw CocoaError(.fileWriteNoPermission) }
            return try await store.save(document, source: source)
        }
    }
}

private struct DocumentWorkspace: View {
    @Bindable var session: DocumentSession
    let collections: [String]
    let create: @Sendable (String, String, String) async throws -> StoredDocument
    let close: () -> Void
    @State private var closing = false
    @State private var namingDestination = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var actionLayout: AnyLayout {
        dynamicTypeSize > .large ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading) {
                actionLayout {
                    Button("Close") {
                        closing = true
                        Task { if await session.flush() { close() }; closing = false }
                    }.foregroundStyle(.primary).frame(minHeight: 44)
                    .accessibilityLabel("Close document").accessibilityIdentifier("close-document")
                    .disabled(closing || session.model.composing || session.isChangingDestination)
                    Button { session.prepareSaveAsDialog(); namingDestination = true } label: {
                        Text("Save as").fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(.primary).frame(minHeight: 44)
                    .accessibilityLabel("Save as new document").accessibilityIdentifier("save-as-document")
                    .disabled(closing || session.model.composing || session.isChangingDestination)
                }
                Text(session.status).accessibilityIdentifier("document-save-status")
                if let recoveryStatus = session.recoveryStatus {
                    Text(recoveryStatus).accessibilityIdentifier("document-recovery-status")
                }
                if session.canKeepRecovery && !session.canClose {
                    Button("Close with recovery copy") {
                        if session.prepareRecoveryClose() { close() }
                    }.foregroundStyle(.primary).frame(minHeight: 44).accessibilityIdentifier("close-with-recovery")
                }
                if session.errorMessage != nil || session.document.durabilityWarning != nil {
                    Button("Retry save") { Task { _ = await session.flush() } }.foregroundStyle(.primary).frame(minHeight: 44).accessibilityIdentifier("retry-save")
                }
            }.font(.body).frame(maxWidth: .infinity, alignment: .leading).padding()
            EditorScreen(model: session.model, title: session.document.name, onEdit: { session.scheduleSave() })
        }
        .interactiveDismissDisabled(!session.canClose)
        .sheet(isPresented: $namingDestination, onDismiss: { session.resumeAfterSaveAsDialog() }) {
            SaveDocumentAsSheet(session: session, collections: collections, create: create) { namingDestination = false }
        }
    }
}
