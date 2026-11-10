import AppKit
import SwiftUI

/// A plain source field. Attaching a newly created editor requests focus once;
/// observation-driven updates never reclaim the keyboard from naming sheets.
@MainActor final class MacSourceTextView: NSTextView {
    private var requestedInitialFocus = false
    var onTextStateChanged: (@MainActor () -> Void)?

    override var isEditable: Bool {
        didSet { requestInitialFocusIfPossible() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestInitialFocusIfPossible()
    }

    private func requestInitialFocusIfPossible() {
        guard let window, isEditable, !requestedInitialFocus else { return }
        requestedInitialFocus = true
        window.makeFirstResponder(self)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextStateChanged?()
    }
}

struct MacSourceEditor: NSViewRepresentable {
    let value: String
    let selection: NSRange
    let isEditable: Bool
    var accessibilityLabel: String = "Document source"
    let onChange: @MainActor (String, Bool, NSRange) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        let text = MacSourceTextView(frame: .zero)
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
        text.isSelectable = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        text.setAccessibilityLabel(accessibilityLabel)
        Self.apply(text, value: value, selection: selection, isEditable: isEditable)
        Self.restoreSelection(selection, in: text)
        text.delegate = context.coordinator
        text.onTextStateChanged = { [weak text, weak coordinator = context.coordinator] in
            if let text { coordinator?.report(text) }
        }
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let text = scroll.documentView as? NSTextView else { return }
        text.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.isApplying = true
        Self.apply(text, value: value, selection: selection, isEditable: isEditable)
        context.coordinator.isApplying = false
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let text = scroll.documentView as? NSTextView else { return }
        coordinator.finishComposition(text)
        (text as? MacSourceTextView)?.onTextStateChanged = nil
        text.delegate = nil
    }

    static func restoreSelection(_ selection: NSRange, in text: NSTextView) {
        let range = SourceSelection.isValid(selection, in: text.string) ? selection : SourceSelection.beginning
        text.setSelectedRange(range)
    }

    static func apply(_ text: NSTextView, value: String, selection: NSRange, isEditable: Bool) {
        // Even a canonically equivalent String can contain different source
        // bytes. Never replace marked text or reset a live equal-byte caret.
        guard !text.hasMarkedText() else { return }
        text.isEditable = isEditable
        guard !SourceSelection.sameText(text.string, value) else { return }
        text.string = value
        restoreSelection(selection, in: text)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: @MainActor (String, Bool, NSRange) -> Void
        var isApplying = false

        init(onChange: @escaping @MainActor (String, Bool, NSRange) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            if let text = notification.object as? NSTextView { report(text) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let text = notification.object as? NSTextView { report(text) }
        }

        func report(_ text: NSTextView) {
            guard !isApplying else { return }
            onChange(text.string, text.hasMarkedText(), text.selectedRange())
        }

        func finishComposition(_ text: NSTextView) {
            if text.hasMarkedText() { text.unmarkText() }
            report(text)
        }
    }
}
