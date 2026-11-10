import SwiftUI

struct SaveDocumentAsSheet: View {
    @Bindable var session: DocumentSession
    let collections: [String]
    let create: @Sendable (String, String, String) async throws -> StoredDocument
    let close: () -> Void
    private let fileExtension: String
    @State private var collection: String
    @State private var name: String

    init(session: DocumentSession, collections: [String], create: @escaping @Sendable (String, String, String) async throws -> StoredDocument, close: @escaping () -> Void) {
        self.session = session
        self.collections = collections
        self.create = create
        self.close = close
        fileExtension = (session.document.name as NSString).pathExtension
        _collection = State(initialValue: session.document.collection)
        _name = State(initialValue: (session.document.name as NSString).deletingPathExtension + " copy")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Creates a new file and continues editing it.").fixedSize(horizontal: false, vertical: true)
                    Text("Linked files are not copied.").fixedSize(horizontal: false, vertical: true)
                    Text("Collection").font(.headline)
                    ForEach(collections, id: \.self) { item in
                        Button { collection = item } label: {
                            HStack {
                                Text(item).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if collection == item { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                        .accessibilityValue(collection == item ? "Selected" : "")
                        .accessibilityIdentifier("save-as-collection-\(item)")
                    }
                    Text("New document name").font(.headline)
                    TextField("Document name", text: $name, axis: .vertical)
                        .textFieldStyle(.roundedBorder).frame(minHeight: 44).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("New document name").accessibilityIdentifier("save-as-name")
                    Button("Clear name") { name = "" }
                        .foregroundStyle(.primary).frame(minHeight: 44).accessibilityIdentifier("clear-save-as-name")
                    Text("File type: .\(fileExtension)")
                    if let error = session.destinationError {
                        Text(error).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("save-as-error")
                    }
                }.padding()
            }.font(.body).disabled(session.isChangingDestination)
            .navigationTitle("Save as").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading) {
                    Button {
                        let filename = name + "." + fileExtension
                        let destination = collection
                        Task {
                            if await session.saveAs(collection: destination, name: filename, create: create) != nil { close() }
                        }
                    } label: {
                        Text("Save new document").lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    }.disabled(name.isEmpty || collection.isEmpty || session.isChangingDestination || session.model.composing)
                    .accessibilityIdentifier("confirm-save-as")
                    Button("Cancel") { close() }.disabled(session.isChangingDestination).accessibilityIdentifier("cancel-save-as")
                }.font(.body).buttonStyle(.borderedProminent).controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Color(red: 0.35, green: 0.25, blue: 0.05))
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(Color(uiColor: .systemBackground))
            }
        }.interactiveDismissDisabled(session.isChangingDestination)
    }
}
