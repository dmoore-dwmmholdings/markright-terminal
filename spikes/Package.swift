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
                "DeclarativeDecoder.swift",
                "Editor.swift",
                "RecoveryWorkspace.swift",
                "SaveDocumentAsSheet.swift"
            ],
            sources: [
                "EditorModel.swift",
                "SourceSelection.swift",
                "CollectionStore.swift",
                "RecoveryDraft.swift",
                "DocumentSession.swift"
            ]
        ),
        .testTarget(
            name: "MarkrightEditorSpikeTests",
            dependencies: ["MarkrightEditorSpike"],
            path: "ios-editor/Tests",
            exclude: [
                "DeclarativeDecoderTests.swift",
                "EditorModelTests.swift",
                "NativeSelectionTests.swift"
            ],
            sources: [
                "NativeTestDirectory.swift",
                "CollectionStoreTests.swift",
                "DocumentSessionTests.swift",
                "RecoveryStoreTests.swift",
                "RecoverySessionTests.swift",
                "SaveAsSessionTests.swift",
                "SaveAsStoreTests.swift"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
