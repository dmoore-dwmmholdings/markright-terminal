import SwiftUI
import UIKit

@MainActor final class SourceTextView: UITextView {
    var focusesOnAttachment = true
    var allowsMarkdownInsertion = true
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil && focusesOnAttachment else { return }
        focusesOnAttachment = false
        becomeFirstResponder()
        scrollRangeToVisible(selectedRange)
    }

    func makeMarkdownMenu() -> UIMenu {
        guard allowsMarkdownInsertion else { return UIMenu(title: "Insert Markdown", children: []) }
        let available = window != nil && isFirstResponder && isEditable && markedTextRange == nil && selectedRanges.count == 1
        let actions = MarkdownInsertionCommand.allCases.map { command in
            let plan = available ? MarkdownInsertionPlan.make(command: command, source: text, selection: selectedRange) : nil
            return UIAction(title: command.title, attributes: plan == nil ? [.disabled] : []) { [weak self, plan] _ in
                guard let self, let plan else { return }
                self.applyMarkdownInsertion(plan)
            }
        }
        return UIMenu(title: "Insert Markdown", children: actions)
    }

    @discardableResult func applyMarkdownInsertion(_ plan: MarkdownInsertionPlan) -> Bool {
        guard allowsMarkdownInsertion, window != nil, isFirstResponder, isEditable, markedTextRange == nil, selectedRanges.count == 1,
              plan.matches(source: text, selection: selectedRange) else { return false }
        let expected = (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
        let undo = undoManager
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping() }
        // The validated current selection is exactly the captured replacement
        // range. Native insertion owns undo and text-system notifications.
        insertText(plan.replacement)
        guard SourceSelection.sameText(text, expected), SourceSelection.isValid(plan.selectionAfter, in: text) else { return false }
        selectedRange = plan.selectionAfter
        undo?.setActionName("Insert Markdown")
        // UIKit programmatic input paths need not deliver every delegate event.
        // Reuse the existing reporter for exact source and the final selection.
        (delegate as? NativeSourceEditor.Coordinator)?.report(self)
        return true
    }
}

struct NativeSourceEditor: UIViewRepresentable {
    let value: String
    let id: Int
    var selection = SourceSelection.beginning
    var wholeDocument = false
    let onChange: (String, Bool, NSRange) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> UITextView {
        let view = SourceTextView()
        view.allowsMarkdownInsertion = wholeDocument
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .secondarySystemBackground
        view.isScrollEnabled = wholeDocument
        // Raw source must not be rewritten by prose-oriented keyboard services.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.accessibilityIdentifier = wholeDocument ? "document-source-editor" : "source-editor-\(id)"
        view.accessibilityLabel = wholeDocument ? "Document Markdown source" : "Source for block \(id)"
        view.text = value
        Self.restoreSelection(selection, in: view)
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        (view as? SourceTextView)?.allowsMarkdownInsertion = wholeDocument
        Self.apply(value, selection: selection, to: view)
    }
    static func apply(_ value: String, selection: NSRange, to view: UITextView) {
        // Avoid selection resets and marked-text replacement during SwiftUI updates.
        if view.markedTextRange == nil && !SourceSelection.sameText(view.text, value) {
            let delegate = view.delegate
            view.delegate = nil
            view.text = value
            Self.restoreSelection(selection, in: view)
            view.delegate = delegate
        }
    }
    static func restoreSelection(_ range: NSRange, in view: UITextView) {
        view.selectedRange = SourceSelection.isValid(range, in: view.text) ? range : SourceSelection.beginning
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.finishComposition(view)
        (view as? SourceTextView)?.focusesOnAttachment = false
        view.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (String, Bool, NSRange) -> Void
        init(onChange: @escaping (String, Bool, NSRange) -> Void) { self.onChange = onChange }
        func finishComposition(_ textView: UITextView) {
            // Native teardown commits visible marked text before the view disappears.
            textView.unmarkText()
            onChange(textView.text, false, textView.selectedRange)
        }
        func textViewDidEndEditing(_ textView: UITextView) { finishComposition(textView) }
        func report(_ textView: UITextView) { onChange(textView.text, textView.markedTextRange != nil, textView.selectedRange) }
        func textViewDidChange(_ textView: UITextView) { report(textView) }
        func textViewDidChangeSelection(_ textView: UITextView) {
            report(textView)
        }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            // On iOS 26 UIKit falls back to this method with a union range when
            // the newer multi-range delegate method is absent. Refuse both a
            // multi-selection and any range differing from the real selection.
            guard let source = textView as? SourceTextView else { return nil }
            guard source.allowsMarkdownInsertion else { return UIMenu(children: suggestedActions) }
            guard source.selectedRanges.count == 1,
                  range == source.selectedRange else { return nil }
            return UIMenu(children: suggestedActions + [source.makeMarkdownMenu()])
        }
    }
}

@main struct EditorSpikeApp: App {
    private let store = CollectionStore(root: CollectionLibrary.rootURL)
    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--editor-fixture") { EditorScreen() }
                else { CollectionLibrary(store: store) }
            }.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : nil)
        }
    }
}
struct EditorScreen: View {
    @State private var model: EditorModel
    private let title: String
    private let onEdit: (() -> Void)?
    init(model: EditorModel? = nil, title: String = "Markright spike", onEdit: (() -> Void)? = nil) {
        _model = State(initialValue: model ?? EditorModel(source: EditorModel.launchSource))
        self.title = title
        self.onEdit = onEdit
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var actionLayout: AnyLayout {
        dynamicTypeSize > .large ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
    }
    private func readingText(_ block: SourceBlock) -> Text {
        if block.atomic { return Text(block.source) }
        let preview = EditorModel.previewText(block.source.isEmpty ? " " : block.source)
        if preview.runs.contains(where: { !($0.inlinePresentationIntent?.isEmpty ?? true) }) { return Text(preview) }
        return Text(String(preview.characters))
    }
    @ViewBuilder private var actionButtons: some View {
        if !model.readingMode {
            if !model.sourceMode {
                Button("Source") { model.showSource() }
                    .accessibilityIdentifier("show-document-source")
                    .accessibilityHint("Edit the complete Markdown document")
                    .disabled(model.composing)
            }
            Button("Done editing") { model.finish() }
                .accessibilityIdentifier("finish-editing").disabled(model.composing)
        }
        Button(model.readingMode ? "Exit reading" : "Read") { model.setReadingMode(!model.readingMode) }
            .id(model.readingMode)
            .accessibilityLabel(model.readingMode ? "Exit reading" : "Reading mode")
            .accessibilityIdentifier("toggle-reading-mode")
            .accessibilityValue(model.readingMode ? "On" : "Off")
            .disabled(model.composing)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if model.retainsReadingRows {
                    VStack(alignment: .leading, spacing: 12) { documentRows }.padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) { documentRows }.padding()
                }
            }
            .navigationTitle(title)
            .safeAreaInset(edge: .bottom) {
                actionLayout { actionButtons }
                .font(.body).buttonStyle(.borderedProminent).controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Color(red: 0.35, green: 0.25, blue: 0.05))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
        }
        .onChange(of: model.sourceRevision) { onEdit?() }
        .onChange(of: model.composing) { _, composing in if !composing { onEdit?() } }
    }
    @ViewBuilder private var documentRows: some View {
        Text("Interaction prototype. Not a complete Markdown editor.").font(.caption).foregroundStyle(.primary)
        if model.sourceMode {
            let generation = model.editingGeneration
            NativeSourceEditor(value: model.documentSource, id: -1, selection: model.documentSelection, wholeDocument: true) { value, composing, selection in
                model.updateDocumentSource(value, composing: composing, generation: generation, selection: selection)
            }.id(generation).frame(height: 500)
        } else {
            ForEach(model.blocks) { block in
                if model.readingMode {
                    readingText(block)
                        .font(block.atomic ? .system(.body, design: .monospaced) : .body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("reading-\(block.id)")
                } else if model.active == block.id {
                    let generation = model.editingGeneration
                    NativeSourceEditor(value: block.source, id: block.id, selection: model.selection(for: block.id)) { value, composing, selection in
                        model.updateBlockFromEditor(block.id, value, composing: composing, generation: generation, selection: selection)
                    }.id(generation).frame(minHeight: block.atomic ? 150 : 64)
                } else {
                    Button { model.activate(block.id) } label: {
                        Group {
                            if block.atomic { Text(block.source).font(.system(.body, design: .monospaced)) }
                            else { Text(EditorModel.previewText(block.source)) }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("preview-\(block.id)")
                    .accessibilityLabel(block.source.isEmpty ? "Empty line" : block.source)
                    .accessibilityHint("Double tap to edit source")
                }
            }
        }
    }
}
