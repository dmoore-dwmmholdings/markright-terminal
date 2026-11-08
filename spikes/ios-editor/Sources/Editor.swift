import SwiftUI
import UIKit

// Native interaction spike only: fixture-level block grouping, not a CommonMark parser.
struct SourceBlock: Identifiable, Equatable {
    let id: Int
    var source: String
    let atomic: Bool
}
@MainActor @Observable final class EditorModel {
    var blocks: [SourceBlock]
    var active: Int?
    var composing = false
    static let sample = "# Markright Terminal\nNative **preview** example\n\n```swift\nlet value = 42\n```\n\n| Field | Value |\n| --- | --- |\n| status | ready |\n\nUnicode 😀 and café"
    static var launchSource: String {
        if ProcessInfo.processInfo.arguments.contains("--large-document") {
            return String(String(repeating: "Plain **preview** line with source.\n", count: 30_000).prefix(1_000_000))
        }
        return sample
    }
    init(source: String) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var groups: [SourceBlock] = []
        var i = 0
        while i < lines.count {
            let start = i
            let fence = lines[i].hasPrefix("```")
            let table = lines[i].hasPrefix("|")
            i += 1
            if fence {
                while i < lines.count { let close = lines[i].hasPrefix("```"); i += 1; if close { break } }
            } else if table {
                while i < lines.count && lines[i].hasPrefix("|") { i += 1 }
            }
            groups.append(SourceBlock(id: start, source: lines[start..<i].joined(separator: "\n"), atomic: fence || table))
        }
        blocks = groups
    }
    var source: String { blocks.map(\.source).joined(separator: "\n") }
    func activate(_ id: Int) { if !composing { active = id } }
    func finish() { if !composing { active = nil } }
    func update(_ id: Int, _ source: String) {
        guard let index = blocks.firstIndex(where: {$0.id == id}) else { return }
        blocks[index].source = source
    }
}

struct NativeSourceEditor: UIViewRepresentable {
    let value: String
    let id: Int
    let onChange: (String, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .secondarySystemBackground
        view.isScrollEnabled = false
        // Raw source must not be rewritten by prose-oriented keyboard services.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.accessibilityIdentifier = "source-editor-\(id)"
        view.accessibilityLabel = "Source for block \(id)"
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
    var body: some Scene { WindowGroup { EditorScreen() } }
}
struct EditorScreen: View {
    @State private var model = EditorModel(source: EditorModel.launchSource)
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Interaction prototype. Not a complete Markdown editor.").font(.caption).foregroundStyle(.secondary)
                    ForEach(model.blocks) { block in
                        if model.active == block.id {
                            NativeSourceEditor(value: block.source, id: block.id) { value, composing in
                                model.composing = composing
                                model.update(block.id, value)
                            }.frame(minHeight: block.atomic ? 150 : 64)
                        } else {
                            Button { model.activate(block.id) } label: {
                                Group {
                                    if block.atomic { Text(block.source).font(.system(.body, design: .monospaced)) }
                                    else { Text((try? AttributedString(markdown: block.source)) ?? AttributedString(block.source.isEmpty ? " " : block.source)) }
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preview-\(block.id)")
                            .accessibilityLabel(block.source.isEmpty ? "Empty line" : block.source)
                            .accessibilityHint("Double tap to edit source")
                        }
                    }
                }.padding()
            }
            .navigationTitle("Markright spike")
            .toolbar { Button("Done editing") { model.finish() }.accessibilityIdentifier("finish-editing").disabled(model.composing) }
        }
    }
}
