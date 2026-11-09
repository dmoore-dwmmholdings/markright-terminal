import SwiftUI
import WebKit

@main struct MarkrightMacEditorSpikeApp: App {
    var body: some Scene {
        Window("Markright macOS research", id: "markright-research") {
            ResearchEditorScreen()
        }
        .defaultSize(width: 1024, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ResearchEditorScreen: View {
    @State private var status = "Loading the bundled synthetic fixture…"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Research host · Temporary edits")
                    .font(.headline)
                Text("Synthetic fixture only. No file saving, collections, accounts or sync. Closing the window discards edits.")
                    .font(.callout)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("research-status")
            }
            .padding()
            Divider()
            BundledEditorView(status: $status)
        }
        .frame(minWidth: 760, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("MRK-9 experiment · Not a production app")
                    .font(.caption)
            }
        }
    }
}

struct BundledEditorView: NSViewRepresentable {
    @Binding var status: String

    func makeCoordinator() -> Coordinator { Coordinator(status: $status) }

    func makeNSView(context: Context) -> WKWebView {
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
            context.coordinator.status.wrappedValue = "Bundled fixture missing. Run prepare-resources.mjs and rebuild."
            let view = WKWebView(frame: .zero, configuration: BundledEditorController.makeConfiguration())
            view.setAccessibilityLabel("Markright synthetic research editor")
            return view
        }
        let coordinator = context.coordinator
        let controller = BundledEditorController(pageURL: page) { [weak coordinator] message in
            coordinator?.status.wrappedValue = message
        }
        coordinator.controller = controller
        controller.load()
        return controller.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.status = $status
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.controller?.stop()
        coordinator.controller = nil
    }

    @MainActor final class Coordinator: NSObject {
        var status: Binding<String>
        var controller: BundledEditorController?

        init(status: Binding<String>) { self.status = status }
    }
}
