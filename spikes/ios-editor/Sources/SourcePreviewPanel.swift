import SwiftUI

/// One-way display of a pure projection. This view has no editor binding,
/// callback, navigation action, selectable text, or source mutation capability.
struct SourcePreviewPanel: View {
    let source: String
    let selection: NSRange
    let composing: Bool

    var body: some View {
        let projection = SourcePreviewProjection.make(source: source, selection: selection, composing: composing)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Live preview").font(.headline)
                if let message = projection.message {
                    Text(verbatim: message)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("live-preview-status")
                } else {
                    Text("Preview ready").accessibilityIdentifier("live-preview-status")
                }
                Text("Partial inline preview. Active text, recognized backtick fences, table rows, and unsupported content remain literal source.")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(projection.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        if row.isActive {
                            Text("Active source").font(.caption)
                        }
                        if row.isLiteral {
                            Text(verbatim: row.source)
                                .font(.system(.body, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(row.display)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("live-preview-row-\(row.id)")
                }
                Text("Preview limit: 64 KiB of source and 256 rows. Long rows stay literal source.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-preview-panel")
    }
}
