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

    override func menu(for event: NSEvent) -> NSMenu? {
        // AppKit first resolves the contextual selection. Copy its menu so a
        // retained/cached native menu never accumulates plans from older clicks.
        let menu = (super.menu(for: event)?.copy() as? NSMenu) ?? NSMenu()
        if isEditable {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Insert Markdown", action: nil, keyEquivalent: "")
            item.submenu = makeMarkdownMenu()
            menu.addItem(item)
            menu.addItem(makeTaskMarkerItem())
            menu.addItem(makeSourceLineSelectionItem())
        }
        return menu
    }

    func makeMarkdownMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert Markdown")
        menu.autoenablesItems = false
        let available = window != nil && window?.firstResponder === self && isEditable &&
            !hasMarkedText() && selectedRanges.count == 1
        for command in MarkdownInsertionCommand.allCases {
            let plan = available ? MarkdownInsertionPlan.make(command: command, source: string, selection: selectedRange()) : nil
            menu.addItem(MacMarkdownInsertionMenuItem(title: command.title, sourceView: self, plan: plan))
        }
        return menu
    }

    func makeTaskMarkerItem() -> NSMenuItem {
        let available = window != nil && window?.firstResponder === self && isEditable &&
            !hasMarkedText() && selectedRanges.count == 1
        let plan = available ? TaskMarkerEdit.make(source: string, selection: selectedRange()) : nil
        return MacMarkdownInsertionMenuItem(title: TaskMarkerEdit.title, sourceView: self, plan: plan)
    }

    func makeSourceLineSelectionItem() -> NSMenuItem {
        let available = window != nil && window?.firstResponder === self && isEditable &&
            !hasMarkedText() && selectedRanges.count == 1
        let plan = available ? SourceLineSelection.make(source: string, selection: selectedRange()) : nil
        return MacSourceNavigationMenuItem(title: SourceLineSelection.title, sourceView: self, plan: plan)
    }

    /// Selection-only: moves the native selection and reports it through the
    /// same coordinator as typing. No source edit, undo step or generation change.
    @discardableResult func applySourceNavigation(_ plan: SourceNavigationPlan) -> Bool {
        guard let window, window.firstResponder === self, isEditable, !hasMarkedText(),
              selectedRanges.count == 1, plan.matches(source: string, selection: selectedRange()) else { return false }
        setSelectedRange(plan.destination)
        scrollRangeToVisible(plan.destination)
        onTextStateChanged?()
        return selectedRange() == plan.destination
    }

    @discardableResult func applyMarkdownInsertion(_ plan: MarkdownInsertionPlan) -> Bool {
        guard let window, window.firstResponder === self, isEditable, !hasMarkedText(),
              selectedRanges.count == 1, plan.matches(source: string, selection: selectedRange()) else { return false }
        let expected = (plan.source as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
        breakUndoCoalescing()
        let undo = undoManager
        undo?.beginUndoGrouping()
        defer { undo?.endUndoGrouping(); breakUndoCoalescing() }
        // Undo runs a group's actions in reverse order: this first action runs
        // last on undo (after the text is restored) and the closing one runs
        // last on redo, so each direction ends on its exact selection.
        let selectionToken = plan.restoresSelectionOnUndo ? undo.map { TaskSelectionUndoToken(view: self, undo: $0) } : nil
        if let undo, let selectionToken { registerSelectionUndo(undo, token: selectionToken, select: plan.originalSelection, reverse: nil) }
        insertText(plan.replacement, replacementRange: plan.range)
        guard SourceSelection.sameText(string, expected), SourceSelection.isValid(plan.selectionAfter, in: string) else {
            if let undo, let selectionToken { undo.removeAllActions(withTarget: selectionToken) }
            return false
        }
        setSelectedRange(plan.selectionAfter)
        if let undo, let selectionToken { registerSelectionUndo(undo, token: selectionToken, select: nil, reverse: plan.selectionAfter) }
        undo?.setActionName(plan.actionName)
        // Report through the same native coordinator as ordinary typing. AppKit
        // normally emits both edit and final selection notifications as well.
        onTextStateChanged?()
        return true
    }

    /// Registers a selection-only undo step that, when performed, selects
    /// `select` (if still valid) and registers its mirror for the other direction.
    /// The token is the only target, so a refused edit can drop just these steps.
    private func registerSelectionUndo(_ undo: UndoManager, token: TaskSelectionUndoToken, select: NSRange?, reverse: NSRange?) {
        // The undo manager references its target weakly; the handler retains
        // the main-actor (hence Sendable) token so later steps still run.
        undo.registerUndo(withTarget: token) { [token] _ in
            MainActor.assumeIsolated {
                guard let view = token.view, let undo = token.undo else { return }
                if let select, SourceSelection.isValid(select, in: view.string) {
                    view.setSelectedRange(select)
                    view.onTextStateChanged?()
                }
                view.registerSelectionUndo(undo, token: token, select: reverse, reverse: select)
            }
        }
    }
}

/// NSMenuItem's target is weak. The retained item targets itself and holds only
/// a weak view reference, so an old menu cannot retain or redirect an editor.
@MainActor private final class MacMarkdownInsertionMenuItem: NSMenuItem, NSMenuItemValidation {
    private weak var sourceView: MacSourceTextView?
    private let plan: MarkdownInsertionPlan?

    init(title: String, sourceView: MacSourceTextView, plan: MarkdownInsertionPlan?) {
        self.sourceView = sourceView
        self.plan = plan
        super.init(title: title, action: #selector(insertMarkdown(_:)), keyEquivalent: "")
        target = self
        isEnabled = plan != nil
    }

    required init(coder: NSCoder) {
        plan = nil
        super.init(coder: coder)
        target = self
        action = #selector(insertMarkdown(_:))
        isEnabled = false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let plan, let sourceView, let window = sourceView.window else { return false }
        return window.firstResponder === sourceView && sourceView.isEditable && !sourceView.hasMarkedText() &&
            sourceView.selectedRanges.count == 1 && plan.matches(source: sourceView.string, selection: sourceView.selectedRange())
    }

    @objc private func insertMarkdown(_ sender: Any?) {
        guard let plan else { return }
        sourceView?.applyMarkdownInsertion(plan)
    }
}

/// The item retains its target (itself), but never the source view. Captured
/// plans are checked again by the same selection-only native execution path.
@MainActor private final class MacSourceNavigationMenuItem: NSMenuItem, NSMenuItemValidation {
    private weak var sourceView: MacSourceTextView?
    private let plan: SourceNavigationPlan?

    init(title: String, sourceView: MacSourceTextView, plan: SourceNavigationPlan?) {
        self.sourceView = sourceView; self.plan = plan
        super.init(title: title, action: #selector(navigate(_:)), keyEquivalent: "")
        target = self
        isEnabled = plan != nil
    }
    required init(coder: NSCoder) {
        plan = nil
        super.init(coder: coder)
        isEnabled = false
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let plan, let sourceView, let window = sourceView.window else { return false }
        return window.firstResponder === sourceView && sourceView.isEditable && !sourceView.hasMarkedText() &&
            sourceView.selectedRanges.count == 1 && plan.matches(source: sourceView.string, selection: sourceView.selectedRange())
    }

    @objc private func navigate(_ sender: Any?) {
        guard let plan else { return }
        sourceView?.applySourceNavigation(plan)
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

/// Weak holder for selection-only undo steps; it never retains the editor.
@MainActor private final class TaskSelectionUndoToken {
    weak var view: MacSourceTextView?
    weak var undo: UndoManager?
    init(view: MacSourceTextView, undo: UndoManager) { self.view = view; self.undo = undo }
}
