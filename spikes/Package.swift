// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkrightNativeResearch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkrightNativeResearch", targets: ["MarkrightEditorSpike"])
    ],
    targets: [
        .target(
            name: "MarkrightEditorSpike",
            path: "ios-editor/Sources",
            exclude: [
                "CollectionLibrary.swift",
                "CollectionSearchPanel.swift",
                "DeclarativeDecoder.swift",
                "Editor.swift",
                "RecoveryWorkspace.swift",
                "SaveDocumentAsSheet.swift",
                "SourceCopyTransfer.swift",
                "SourceCopyExporter.swift"
            ],
            sources: [
                "EditorModel.swift",
                "SourceSelection.swift",
                "CollectionStore.swift",
                "CollectionSearch.swift",
                "CollectionSearchModel.swift",
                "RecoveryDraft.swift",
                "DocumentSession.swift",
                "SourceCopyExport.swift",
                "MarkdownInsertion.swift",
                "MarkdownTableInsertion.swift",
                "SourceOutline.swift",
                "SourceSelectionFind.swift"
            ]
        ),
        .testTarget(
            name: "MarkrightEditorSpikeTests",
            dependencies: ["MarkrightEditorSpike"],
            path: "ios-editor/Tests",
            exclude: [
                "DeclarativeDecoderTests.swift",
                "EditorModelTests.swift",
                "NativeSelectionTests.swift",
                "NativeMarkdownInsertionTests.swift",
                "NativeMarkdownStructureInsertionTests.swift",
                "NativeMarkdownListInsertionTests.swift",
                "NativeMarkdownHeadingQuoteInsertionTests.swift",
                "NativeMarkdownTableInsertionTests.swift",
                "NativeSourceOutlineTests.swift",
                "NativeSourceSelectionFindTests.swift"
            ],
            sources: [
                "NativeTestDirectory.swift",
                "CollectionStoreTests.swift",
                "CollectionSearchTests.swift",
                "CollectionSearchModelTests.swift",
                "DocumentSessionTests.swift",
                "RecoveryStoreTests.swift",
                "RecoverySessionTests.swift",
                "SaveAsSessionTests.swift",
                "SaveAsStoreTests.swift",
                "SourceCopyExportTests.swift",
                "MarkdownInsertionTests.swift",
                "MarkdownStructureInsertionTests.swift",
                "MarkdownListInsertionTests.swift",
                "MarkdownHeadingQuoteInsertionTests.swift",
                "MarkdownTableInsertionTests.swift",
                "SourceOutlineTests.swift",
                "SourceSelectionFindTests.swift"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
