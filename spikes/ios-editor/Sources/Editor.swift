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
    var blocks: [SourceBlock]
    var active: Int?
    var composing = false
    var sourceMode = false
    var documentSource = ""
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
    var source: String { sourceMode ? documentSource : blocks.map { $0.source + $0.separatorAfter }.joined() }
    func activate(_ id: Int) {
        guard !composing && !sourceMode else { return }
        if active != id { editingGeneration += 1 }
        active = id
    }
    func showSource() {
        guard !composing && !sourceMode else { return }
        documentSource = source
        editingGeneration += 1
        active = nil
        sourceMode = true
    }
    func updateDocumentSource(_ value: String, composing: Bool, generation: Int) {
        guard sourceMode && generation == editingGeneration else { return }
        self.composing = composing
        documentSource = value
    }
    func updateBlockFromEditor(_ id: Int, _ value: String, composing: Bool, generation: Int) {
        guard !sourceMode && active == id && generation == editingGeneration else { return }
        self.composing = composing
        update(id, value)
    }
    func finish() {
        guard !composing else { return }
        editingGeneration += 1
        if sourceMode {
            blocks = EditorModel(source: documentSource).blocks
            sourceMode = false
            documentSource = ""
        }
        active = nil
    }
    func update(_ id: Int, _ source: String) {
        guard let index = blocks.firstIndex(where: {$0.id == id}) else { return }
        blocks[index].source = source
    }
}

struct NativeSourceEditor: UIViewRepresentable {
    let value: String
    let id: Int
    var wholeDocument = false
    let onChange: (String, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        // Avoid selection resets and marked-text replacement during SwiftUI updates.
        if view.markedTextRange == nil && view.text != value { view.text = value }
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.finishComposition(view)
        view.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (String, Bool) -> Void
        init(onChange: @escaping (String, Bool) -> Void) { self.onChange = onChange }
        func finishComposition(_ textView: UITextView) {
            // Native teardown commits visible marked text before the view disappears.
            textView.unmarkText()
            onChange(textView.text, false)
        }
        func textViewDidEndEditing(_ textView: UITextView) { finishComposition(textView) }
        func textViewDidChange(_ textView: UITextView) { onChange(textView.text, textView.markedTextRange != nil) }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.markedTextRange == nil { onChange(textView.text, false) }
        }
    }
}

@main struct EditorSpikeApp: App {
    var body: some Scene { WindowGroup { EditorScreen().preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : nil) } }
}
struct EditorScreen: View {
    @State private var model = EditorModel(source: EditorModel.launchSource)
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Interaction prototype. Not a complete Markdown editor.").font(.caption).foregroundStyle(.primary)
                    if model.sourceMode {
                        let generation = model.editingGeneration
                        NativeSourceEditor(value: model.documentSource, id: -1, wholeDocument: true) { value, composing in
                            model.updateDocumentSource(value, composing: composing, generation: generation)
                        }.frame(height: 500)
                    } else {
                    ForEach(model.blocks) { block in
                        if model.active == block.id {
                            let generation = model.editingGeneration
                            NativeSourceEditor(value: block.source, id: block.id) { value, composing in
                                model.updateBlockFromEditor(block.id, value, composing: composing, generation: generation)
                            }.frame(minHeight: block.atomic ? 150 : 64)
                        } else {
                            Button { model.activate(block.id) } label: {
                                Group {
                                    if block.atomic { Text(block.source).font(.system(.body, design: .monospaced)) }
                                    else { Text((try? AttributedString(markdown: block.source)) ?? AttributedString(block.source.isEmpty ? " " : block.source)) }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preview-\(block.id)")
                            .accessibilityLabel(block.source.isEmpty ? "Empty line" : block.source)
                            .accessibilityHint("Double tap to edit source")
                        }
                    }
                    }
                }.padding()
            }
            .navigationTitle("Markright spike")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if !model.sourceMode {
                        Button("Source") { model.showSource() }
                            .accessibilityIdentifier("show-document-source")
                            .accessibilityHint("Edit the complete Markdown document")
                            .disabled(model.composing)
                    }
                    Button("Done editing") { model.finish() }
                        .accessibilityIdentifier("finish-editing").disabled(model.composing)
                }
                    .font(.body).buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(Color(red: 0.35, green: 0.25, blue: 0.05))
                    .padding()
            }
        }
    }
}
