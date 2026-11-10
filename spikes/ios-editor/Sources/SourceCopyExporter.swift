import SwiftUI

/// Mount once per immutable request.id. Escaping exporter callbacks retain only
/// the request/model, never this presenter's disappearing SwiftUI state or URL.
struct SourceCopyExporter: View {
    let request: SourceCopySnapshot
    let model: SourceCopyExportModel
    @State private var isPresented = true

    var body: some View {
        let transfer = SourceCopyTransfer(snapshot: request)
        Color.clear.frame(width: 0, height: 0)
            .fileExporter(isPresented: $isPresented, item: transfer, contentTypes: [transfer.contentType],
                          defaultFilename: request.suggestedFilename,
                          onCompletion: { [request, model] result in
                let outcome = result.map { _ in () }
                Task { @MainActor in model.finish(id: request.id, result: outcome) }
            }, onCancellation: { [request, model] in
                Task { @MainActor in model.cancel(id: request.id) }
            })
    }
}
