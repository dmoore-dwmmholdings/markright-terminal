import SwiftUI
import UIKit

// Native interaction spike only: fixture-level block grouping, not a CommonMark parser.
struct SourceBlock: Identifiable, Equatable {
    let id: Int
    var source: String
    // The boundary belongs to the source document, not the editable block text.
    let separatorAfter: String
    let atomic: Bool
}
@MainActor @Observable final class EditorModel {
    private(set) var blocks: [SourceBlock]
    private(set) var active: Int?
    var composing = false
    private(set) var sourceMode = false
    private(set) var readingMode = false
    private(set) var documentSource = ""
    private(set) var documentSelection = SourceSelection.beginning
    private(set) var sourceRevision = 0
    private var documentSelectionRevision: Int?
    private var blockSelections: [Int: NSRange] = [:]
    private(set) var editingGeneration = 0
    static let sample = "# Markright Terminal\nNative **preview** example\n\n```swift\nlet value = 42\n```\n\n| Field | Value |\n| --- | --- |\n| status | ready |\n\nUnicode 😀 and café"
    static var launchSource: String {
        if ProcessInfo.processInfo.arguments.contains("--static-calculator") {
            guard let url = Bundle.main.url(forResource: "calculator-static", withExtension: "md"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                return "Static calculator fixture unavailable. No document code was executed."
            }
            return source
        }
        if ProcessInfo.processInfo.arguments.contains("--large-document") {
            return String(String(repeating: "Plain **preview** line with source.\n", count: 30_000).prefix(1_000_000))
        }
        return sample
    }
    init(source: String) {
        let lines = Self.physicalLines(source)
        var groups: [SourceBlock] = []
        var i = 0
        while i < lines.count {
            let start = i
            let fence = lines[i].text.hasPrefix("```")
            let table = lines[i].text.hasPrefix("|")
            i += 1
            if fence {
                while i < lines.count { let close = lines[i].text.hasPrefix("```"); i += 1; if close { break } }
            } else if table {
                while i < lines.count && lines[i].text.hasPrefix("|") { i += 1 }
            }
            let body = lines[start..<i].enumerated().map { offset, line in
                line.text + (offset < i - start - 1 ? line.ending : "")
            }.joined()
            groups.append(SourceBlock(id: start, source: body, separatorAfter: lines[i - 1].ending, atomic: fence || table))
        }
        blocks = groups
    }
    // Split scalars rather than Characters: Swift treats CRLF as one grapheme.
    // Only LF/CRLF/CR are document line endings; other Unicode scalars stay text.
    private static func physicalLines(_ source: String) -> [(text: String, ending: String)] {
        let scalars = source.unicodeScalars
        var start = scalars.startIndex
        var cursor = start
        var lines: [(text: String, ending: String)] = []
        while cursor < scalars.endIndex {
            if scalars[cursor] == "\r" || scalars[cursor] == "\n" {
                let boundary = cursor
                let carriageReturn = scalars[cursor] == "\r"
                scalars.formIndex(after: &cursor)
                if carriageReturn && cursor < scalars.endIndex && scalars[cursor] == "\n" {
                    scalars.formIndex(after: &cursor)
                }
                lines.append((String(scalars[start..<boundary]), String(scalars[boundary..<cursor])))
                start = cursor
            } else {
                scalars.formIndex(after: &cursor)
            }
        }
        lines.append((String(scalars[start..<scalars.endIndex]), ""))
        return lines
    }
    // A native naming sheet temporarily owns the keyboard. Resume the same
    // source/range in a fresh editor generation after it dismisses, so old
    // coordinator callbacks cannot alter the resumed session.
    func resumeEditorAfterDialog() {
        guard !composing, !readingMode, sourceMode || active != nil else { return }
        editingGeneration += 1
    }
    var source: String { sourceMode ? documentSource : blocks.map { $0.source + $0.separatorAfter }.joined() }
    // Keep short reading documents mounted across Dynamic Type relayout, so
    // accessibility elements do not disappear as earlier rows grow. Bound both
    // row count and text size; large documents retain lazy rendering.
    var retainsReadingRows: Bool {
        guard readingMode && blocks.count <= 128 else { return false }
        var remaining = 65_536
        for block in blocks {
            for text in [block.source, block.separatorAfter] {
                let count = text.utf16.count
                guard count <= remaining else { return false }
                remaining -= count
            }
        }
        return true
    }
    static func previewText(_ source: String) -> AttributedString {
        var text = (try? AttributedString(markdown: source)) ?? AttributedString(source.isEmpty ? " " : source)
        // Reading text must not add a URL-opening capability. Navigation policy
        // and the complete renderer remain separate acceptance gates.
        text.link = nil
        return text
    }
    func activate(_ id: Int) {
        guard !composing && !sourceMode && !readingMode, blocks.contains(where: { $0.id == id }) else { return }
        if active != id {
            editingGeneration += 1
            if blockSelections[id] == nil {
                restoreBlockSelectionFromDocument(id)
                if blockSelections[id] == nil { blockSelections[id] = SourceSelection.beginning }
            }
        }
        active = id
    }
    func showSource() {
        guard !composing && !sourceMode && !readingMode else { return }
        if let active { rememberDocumentSelection(from: active) }
        documentSource = source
        if documentSelectionRevision != sourceRevision {
            documentSelection = SourceSelection.beginning
            documentSelectionRevision = sourceRevision
        }
        editingGeneration += 1
        active = nil
        sourceMode = true
    }
    func updateDocumentSource(_ value: String, composing: Bool, generation: Int, selection: NSRange? = nil) {
        guard !readingMode && sourceMode && generation == editingGeneration else { return }
        self.composing = composing
        if !SourceSelection.sameText(documentSource, value) {
            invalidateDocumentSelection()
            documentSource = value
        }
        if !composing, let selection { saveDocumentSelection(selection, in: value) }
    }
    func updateBlockFromEditor(_ id: Int, _ value: String, composing: Bool, generation: Int, selection: NSRange? = nil) {
        guard !readingMode && !sourceMode && active == id && generation == editingGeneration else { return }
        self.composing = composing
        update(id, value)
        if !composing, let selection {
            blockSelections[id] = SourceSelection.isValid(selection, in: value) ? selection : nil
        }
    }
    func finish() {
        guard !composing && !readingMode else { return }
        editingGeneration += 1
        if sourceMode {
            blocks = EditorModel(source: documentSource).blocks
            blockSelections.removeAll()
            sourceMode = false
            documentSource = ""
        } else if let active {
            rememberDocumentSelection(from: active)
        }
        active = nil
    }
    func setReadingMode(_ enabled: Bool) {
        guard !composing && readingMode != enabled else { return }
        if enabled {
            // Commit whole-source edits and invalidate the departing editor's
            // callbacks before its UIViewRepresentable teardown can run.
            finish()
            readingMode = true
        } else {
            editingGeneration += 1
            readingMode = false
            active = nil
        }
    }
    func update(_ id: Int, _ source: String) {
        guard !readingMode, let index = blocks.firstIndex(where: {$0.id == id}) else { return }
        guard !SourceSelection.sameText(blocks[index].source, source) else { return }
        blockSelections[id] = nil
        invalidateDocumentSelection()
        blocks[index].source = source
    }
    func selection(for id: Int) -> NSRange {
        guard let range = blockSelections[id], let block = blocks.first(where: { $0.id == id }),
              SourceSelection.isValid(range, in: block.source) else { return SourceSelection.beginning }
        return range
    }
    private func invalidateDocumentSelection() {
        sourceRevision += 1
        documentSelectionRevision = nil
        documentSelection = SourceSelection.beginning
    }
    private func saveDocumentSelection(_ range: NSRange, in source: String) {
        guard SourceSelection.isValid(range, in: source) else {
            documentSelection = SourceSelection.beginning
            documentSelectionRevision = nil
            return
        }
        documentSelection = range
        documentSelectionRevision = sourceRevision
    }
    private func rememberDocumentSelection(from id: Int) {
        var offset = 0
        for block in blocks {
            if block.id == id {
                guard let local = blockSelections[id], SourceSelection.isValid(local, in: block.source) else {
                    documentSelection = SourceSelection.beginning
                    documentSelectionRevision = nil
                    return
                }
                saveDocumentSelection(NSRange(location: offset + local.location, length: local.length), in: source)
                return
            }
            offset += block.source.utf16.count + block.separatorAfter.utf16.count
        }
    }
    private func restoreBlockSelectionFromDocument(_ id: Int) {
        guard documentSelectionRevision == sourceRevision else { return }
        var offset = 0
        for block in blocks {
            let count = block.source.utf16.count
            if block.id == id {
                let local = documentSelection.location - offset
                guard local >= 0 && local <= count && documentSelection.length <= count - local else { return }
                let range = NSRange(location: local, length: documentSelection.length)
                if SourceSelection.isValid(range, in: block.source) { blockSelections[id] = range }
                return
            }
            offset += count + block.separatorAfter.utf16.count
        }
    }
}

@MainActor final class SourceTextView: UITextView {
    var focusesOnAttachment = true
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil && focusesOnAttachment else { return }
        focusesOnAttachment = false
        becomeFirstResponder()
        scrollRangeToVisible(selectedRange)
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
        func textViewDidChange(_ textView: UITextView) { onChange(textView.text, textView.markedTextRange != nil, textView.selectedRange) }
        func textViewDidChangeSelection(_ textView: UITextView) {
            onChange(textView.text, textView.markedTextRange != nil, textView.selectedRange)
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
