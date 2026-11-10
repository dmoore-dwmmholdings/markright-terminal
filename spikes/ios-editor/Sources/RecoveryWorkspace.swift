import SwiftUI
import UIKit

struct RecoveryWorkspace: View {
    let draft: RecoveryDraft
    let collections: [String]
    let restore: @MainActor (String, String) async throws -> RecoveryRestoreReceipt
    let close: () -> Void
    @State private var target: String
    @State private var name: String
    @State private var namingCopy = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var receipt: RecoveryRestoreReceipt?

    init(draft: RecoveryDraft, collections: [String], restore: @escaping @MainActor (String, String) async throws -> RecoveryRestoreReceipt, close: @escaping () -> Void) {
        self.draft = draft
        self.collections = collections
        self.restore = restore
        self.close = close
        _target = State(initialValue: collections.contains(draft.collection) ? draft.collection : (collections.first ?? ""))
        _name = State(initialValue: "Recovered " + (draft.name as NSString).deletingPathExtension)
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Original: \(draft.name) in \(draft.collection)").fixedSize(horizontal: false, vertical: true)
                Text("Save a new copy to keep the original unchanged.").fixedSize(horizontal: false, vertical: true)
                if receipt == nil {
                    Picker("Collection", selection: $target) {
                        ForEach(collections, id: \.self) { Text($0).tag($0) }
                    }.tint(.primary).accessibilityIdentifier("recovery-target")
                }
                if let receipt {
                    Text("Recovered copy saved as \(receipt.document.name)").accessibilityIdentifier("recovery-restored")
                    if let warning = receipt.document.durabilityWarning ?? receipt.retirementWarning { Text(warning) }
                }
                if let errorMessage { Text(errorMessage).accessibilityIdentifier("recovery-error") }
                RecoverySourceView(source: draft.source)
            }.font(.body).padding()
            .navigationTitle("Recovered edits").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading) {
                    if receipt == nil {
                        Button { namingCopy = true } label: {
                            Text("Save recovered copy").lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }.disabled(collections.isEmpty || busy).accessibilityIdentifier("save-recovered-copy")
                    }
                    Button("Close") { close() }.disabled(busy).accessibilityIdentifier("close-recovery")
                }.font(.body).buttonStyle(.borderedProminent).controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Color(red: 0.35, green: 0.25, blue: 0.05))
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(Color(uiColor: .systemBackground))
            }
            .alert("Save recovered copy", isPresented: $namingCopy) {
                TextField("Document name", text: $name)
                Button("Save") {
                    let filename = name + "." + (draft.name as NSString).pathExtension
                    let destination = target
                    busy = true
                    Task {
                        defer { busy = false }
                        do { receipt = try await restore(destination, filename); errorMessage = nil }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a new name without a file extension.") }
        }.interactiveDismissDisabled(busy)
    }
}

private struct RecoverySourceView: UIViewRepresentable {
    let source: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.dataDetectorTypes = []
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .secondarySystemBackground
        view.accessibilityLabel = "Recovered source"
        view.accessibilityIdentifier = "recovered-source"
        view.text = source
        return view
    }
    func updateUIView(_ uiView: UITextView, context: Context) {
        if !SourceSelection.sameText(uiView.text, source) { uiView.text = source }
    }
}
