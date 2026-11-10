import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Explicit, read-only search of the selected collection's saved source.
/// The search model never owns or changes an editor session.
struct CollectionSearchPanel: View {
    let collection: String
    let onOpen: @MainActor (String) -> Void
    @State private var model: CollectionSearchModel
    @State private var isExpanded: Bool
    @State private var queryComposing = false
    @ScaledMetric(relativeTo: .body) private var queryHeight = 80.0

    init(store: CollectionStore, collection: String, onOpen: @escaping @MainActor (String) -> Void) {
        self.init(model: CollectionSearchModel(store: store), collection: collection, onOpen: onOpen)
    }

    init(model: CollectionSearchModel, collection: String, initiallyExpanded: Bool = false,
         onOpen: @escaping @MainActor (String) -> Void) {
        self.collection = collection
        self.onOpen = onOpen
        _model = State(initialValue: model)
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if isExpanded {
                    queryComposing = false
                    isExpanded = false
                    model.cancel()
                } else { isExpanded = true }
            } label: {
                Label(isExpanded ? "Hide saved-document search" : "Search saved documents",
                      systemImage: isExpanded ? "chevron.up" : "magnifyingglass")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("collection-search-toggle")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(verbatim: "Saved source in \(collection)").font(.headline)
                Text("Find literal text in saved documents only. Unsaved edits are not searched.")
                    .fixedSize(horizontal: false, vertical: true)
                queryField
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { searchActions }
                    VStack(alignment: .leading, spacing: 8) { searchActions }
                }
                Text("Use a short query. Each search checks up to 64 saved files or 8 MiB, shows up to 50 matching files, and counts up to 100 matches per file.")
                    .fixedSize(horizontal: false, vertical: true)
                searchStatus
            }
        }
        .font(.body)
        .onChange(of: collection, initial: true) { _, value in model.setCollection(value) }
        .onDisappear { model.cancel() }
    }

    private var queryField: some View {
        CollectionSearchQueryEditor(value: model.query) { value, composing in
            queryComposing = composing
            if !SourceSelection.sameText(model.query, value) { model.query = value }
        }
        .frame(height: queryHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.5)))
    }

    @ViewBuilder private var searchActions: some View {
        Button("Search") { runSearch() }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .accessibilityIdentifier("collection-search-run")
            .disabled(queryComposing || model.query.isEmpty || model.isSearching)
        Button("Cancel search") { model.cancel() }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .disabled(!model.isSearching)
        Button("Clear") {
            model.cancel()
            model.query = ""
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .disabled(queryComposing || (model.query.isEmpty && model.report == nil && model.errorMessage == nil))
    }

    private func runSearch() {
        guard model.collection == collection, !queryComposing, !model.isSearching, !model.query.isEmpty else { return }
        model.run()
    }

    @ViewBuilder private var searchStatus: some View {
        if model.isSearching {
            ProgressView("Searching saved source…")
                .accessibilityIdentifier("collection-search-status")
        } else if let error = model.errorMessage {
            Text(verbatim: error)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("collection-search-status")
        } else if let report = model.report, report.collection == collection, model.collection == collection {
            VStack(alignment: .leading, spacing: 12) {
                Text("Searched \(report.searchedDocuments) of \(report.totalDocuments) saved documents. Checked \(report.inspectedDocuments); read budget used \(ByteCountFormatter.string(fromByteCount: Int64(report.processedBytes), countStyle: .file)).")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("collection-search-status")
                if report.hits.isEmpty {
                    Text(report.limited || !report.issues.isEmpty
                         ? "No matches were found in the documents searched. The search did not cover every saved document."
                         : "No matches in the saved documents searched.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Opening a result starts at the beginning; an already-open document keeps its current position. Saved files may have changed since the search.")
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(report.hits) { hit in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: hit.name).font(.headline)
                            Text(hit.moreMatches ? "At least \(hit.matchCount) matches" : "\(hit.matchCount) \(hit.matchCount == 1 ? "match" : "matches")")
                            Text(verbatim: hit.preview)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Button("Open document") {
                                guard model.collection == collection, model.isCurrentResult(report, hit: hit) else { return }
                                onOpen(hit.name)
                            }
                            .foregroundStyle(.primary)
                            .frame(minHeight: 44)
                            .accessibilityLabel(Text(verbatim: "Open document \(hit.name)"))
                            .accessibilityHint("Opens at the beginning unless this document is already open. The saved file may have changed.")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("collection-search-result-\(hit.name)")
                    }
                }
                ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                    Text(verbatim: issue).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, limitation in
                    Text(verbatim: limitation).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Enter text and choose Search.")
                .accessibilityIdentifier("collection-search-status")
        }
    }
}

// This field owns its native text view. It never changes a shared field editor,
// requests focus, inspects the pasteboard, or rewrites Return/pasted newlines.
#if os(macOS)
@MainActor final class CollectionSearchQueryTextView: NSTextView {
    var onTextStateChanged: (@MainActor () -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextStateChanged?()
    }
}

struct CollectionSearchQueryEditor: NSViewRepresentable {
    let value: String
    let onChange: @MainActor (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = CollectionSearchQueryTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
        text.isRichText = false
        text.importsGraphics = false
        text.allowsUndo = true
        text.smartInsertDeleteEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticTextCompletionEnabled = false
        text.enabledTextCheckingTypes = 0
        text.font = .preferredFont(forTextStyle: .body)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 260, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.setAccessibilityLabel("Saved-source search query")
        text.setAccessibilityIdentifier("collection-search-query")
        text.string = value
        text.isEditable = context.environment.isEnabled
        text.delegate = context.coordinator
        text.onTextStateChanged = { [weak text, weak coordinator = context.coordinator] in
            if let text { coordinator?.report(text) }
        }
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard !context.coordinator.isRetired else { return }
        context.coordinator.onChange = onChange
        guard let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.isApplying = true
        Self.apply(text, value: value, isEditable: context.environment.isEnabled)
        context.coordinator.isApplying = false
    }

    static func apply(_ text: NSTextView, value: String, isEditable: Bool) {
        guard !text.hasMarkedText() else { return }
        text.isEditable = isEditable
        guard !SourceSelection.sameText(text.string, value) else { return }
        let selection = text.selectedRange()
        text.string = value
        text.setSelectedRange(SourceSelection.isValid(selection, in: value) ? selection : SourceSelection.beginning)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.retire()
        guard let text = scroll.documentView as? NSTextView else { return }
        (text as? CollectionSearchQueryTextView)?.onTextStateChanged = nil
        text.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: @MainActor (String, Bool) -> Void
        var isApplying = false
        private(set) var isRetired = false
        init(onChange: @escaping @MainActor (String, Bool) -> Void) { self.onChange = onChange }
        func retire() {
            isRetired = true
            onChange = { _, _ in }
        }
        func report(_ text: NSTextView) {
            guard !isRetired, !isApplying else { return }
            onChange(text.string, text.hasMarkedText())
        }
        func textDidChange(_ notification: Notification) {
            if let text = notification.object as? NSTextView { report(text) }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let text = notification.object as? NSTextView { report(text) }
        }
        func textDidEndEditing(_ notification: Notification) {
            if let text = notification.object as? NSTextView { finishComposition(text) }
        }
        func finishComposition(_ text: NSTextView) {
            guard !isRetired else { return }
            if text.hasMarkedText() { text.unmarkText() }
            report(text)
        }
    }
}
#elseif os(iOS)
@MainActor final class CollectionSearchQueryTextView: UITextView {
    var onTextStateChanged: (@MainActor () -> Void)?

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        onTextStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextStateChanged?()
    }
}

struct CollectionSearchQueryEditor: UIViewRepresentable {
    let value: String
    let onChange: @MainActor (String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> CollectionSearchQueryTextView {
        let text = CollectionSearchQueryTextView()
        text.font = .preferredFont(forTextStyle: .body)
        text.adjustsFontForContentSizeCategory = true
        text.backgroundColor = .secondarySystemBackground
        text.isScrollEnabled = true
        text.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        text.smartQuotesType = .no
        text.smartDashesType = .no
        text.smartInsertDeleteType = .no
        text.autocorrectionType = .no
        text.autocapitalizationType = .none
        text.spellCheckingType = .no
        text.inlinePredictionType = .no
        text.allowsEditingTextAttributes = false
        text.dataDetectorTypes = []
        text.textContentType = nil
        text.returnKeyType = .default
        text.accessibilityLabel = "Saved-source search query"
        text.accessibilityIdentifier = "collection-search-query"
        text.text = value
        text.isEditable = context.environment.isEnabled
        text.delegate = context.coordinator
        text.onTextStateChanged = { [weak text, weak coordinator = context.coordinator] in
            if let text { coordinator?.report(text) }
        }
        return text
    }

    func updateUIView(_ text: CollectionSearchQueryTextView, context: Context) {
        guard !context.coordinator.isRetired else { return }
        context.coordinator.onChange = onChange
        context.coordinator.isApplying = true
        Self.apply(text, value: value, isEditable: context.environment.isEnabled)
        context.coordinator.isApplying = false
    }

    static func apply(_ text: UITextView, value: String, isEditable: Bool) {
        guard text.markedTextRange == nil else { return }
        text.isEditable = isEditable
        guard !SourceSelection.sameText(text.text, value) else { return }
        let selection = text.selectedRange
        text.text = value
        text.selectedRange = SourceSelection.isValid(selection, in: value) ? selection : SourceSelection.beginning
    }

    static func dismantleUIView(_ text: CollectionSearchQueryTextView, coordinator: Coordinator) {
        coordinator.retire()
        text.onTextStateChanged = nil
        text.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: @MainActor (String, Bool) -> Void
        var isApplying = false
        private(set) var isRetired = false
        init(onChange: @escaping @MainActor (String, Bool) -> Void) { self.onChange = onChange }
        func retire() {
            isRetired = true
            onChange = { _, _ in }
        }
        func report(_ text: UITextView) {
            guard !isRetired, !isApplying else { return }
            onChange(text.text, text.markedTextRange != nil)
        }
        func textViewDidChange(_ textView: UITextView) { report(textView) }
        func textViewDidChangeSelection(_ textView: UITextView) { report(textView) }
        func textViewDidEndEditing(_ textView: UITextView) { finishComposition(textView) }
        func finishComposition(_ text: UITextView) {
            guard !isRetired else { return }
            if text.markedTextRange != nil { text.unmarkText() }
            report(text)
        }
    }
}
#endif
