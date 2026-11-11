import AppKit
import SwiftUI

// Standalone synthetic calibration only. This entry point has no production
// workspace, document lifecycle, filesystem input, or automatic test actions.
private enum SyntheticCalibrationFixture {
    static let source = "Inactive **bold** and [link label](https://example.invalid).\r\n"
        + "Active *source* with Cafe\u{301} and 😀.\r"
        + "<span>inert HTML</span>\n"
        + "![inert image](https://example.invalid/image.png)\r\n"
        + "```text\n"
        + "inert code: <script>never runs</script>\r"
        + "```\n"
        + "| heading | value |\r\n"
        + "| --- | --- |\r"
        + "| inert | table |\n"

    static let selection = (source as NSString).range(of: "*source*")
    static let windowTitle = "Markright Synthetic Accessibility Calibration"
    static let expectedIDs = [
        "calibration-heading",
        "calibration-plain-text",
        "calibration-preview-toggle",
        "calibration-composition-status",
        "calibration-source-editor",
        "calibration-close",
        "live-preview-panel",
        "live-preview-status"
    ]
}

@MainActor private struct SyntheticCalibrationRoot: View {
    @State private var source: String
    @State private var selection: NSRange
    @State private var composing = false
    @State private var showPreview = true

    init(source: String, selection: NSRange) {
        _source = State(initialValue: source)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Synthetic accessibility calibration")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("calibration-heading")
                Text("Synthetic SwiftUI calibration text")
                    .accessibilityIdentifier("calibration-plain-text")
                HStack(spacing: 20) {
                    Toggle("Show synthetic preview", isOn: $showPreview)
                        .accessibilityIdentifier("calibration-preview-toggle")
                    Text(composing ? "Composition in progress (in memory only)." : "No composition in progress.")
                        .accessibilityIdentifier("calibration-composition-status")
                }
            }
            .padding(16)
            Divider()
            // Keep the native editor in the same unconditional first position.
            // The optional preview never supplies an identity or resets state.
            HStack(spacing: 0) {
                MacSourceEditor(value: source, selection: selection, isEditable: true,
                                accessibilityLabel: "Synthetic Markdown source") { value, isComposing, range in
                    source = value
                    selection = range
                    composing = isComposing
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("calibration-source-editor")
                if showPreview {
                    Divider()
                    SourcePreviewPanel(source: source, selection: selection, composing: composing)
                        .frame(minWidth: 260, idealWidth: 360, maxWidth: 440, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(alignment: .center, spacing: 16) {
                Text("Synthetic, in memory only. Closing discards edits. VoiceOver settings are not changed. This window is not a production workspace or an acceptance result.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Close calibration") {
                    NSApplication.shared.terminate(nil)
                }
                .accessibilityIdentifier("calibration-close")
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalibrationStartup: Encodable {
    let pid: Int32
    let title: String
    let expectedIDs: [String]
    let windowIsVisible: Bool
}

@MainActor private final class SyntheticCalibrationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = SyntheticCalibrationFixture.windowTitle
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SyntheticCalibrationRoot(
            source: SyntheticCalibrationFixture.source, selection: SyntheticCalibrationFixture.selection))
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()

        // These are ordinary app properties and declared identifiers, not an
        // AX observation, accessibility assertion, or runtime pass result.
        let startup = CalibrationStartup(pid: ProcessInfo.processInfo.processIdentifier,
            title: window.title, expectedIDs: SyntheticCalibrationFixture.expectedIDs,
            windowIsVisible: window.isVisible)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(startup), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main private enum SyntheticAXCalibration {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "Usage: Markright AX Calibration --show-synthetic-window\n       Markright AX Calibration --help"
        guard arguments == ["--show-synthetic-window"] else {
            print(usage)
            if arguments != ["--help"] { exit(64) }
            return
        }
        guard SyntheticCalibrationFixture.source.utf8.count < 1024,
              SyntheticCalibrationFixture.selection.length > 0,
              SourceSelection.isValid(SyntheticCalibrationFixture.selection, in: SyntheticCalibrationFixture.source) else {
            exit(70)
        }

        // Every argument and initial-state check precedes application creation.
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Markright AX Calibration")
        let quit = NSMenuItem(title: "Quit Markright AX Calibration", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = app
        applicationMenu.addItem(quit)
        applicationMenuItem.submenu = applicationMenu
        menu.addItem(applicationMenuItem)
        app.mainMenu = menu

        let delegate = SyntheticCalibrationDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
