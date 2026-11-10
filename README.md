# Markright Terminal

Research prototypes for portable Markright documents and native authoring, tracked against the proposed MRK v2 specification. This is not a shipped application or frozen language contract. Documents are never automatically executed, and no Firebase service is provisioned.

The native iOS prototype supports app-owned collections, document editing/autosave, Save As across collections, explicit source/reading modes, selection continuity and recovery checkpoints restored as separate copies. The macOS research app also provides a separate native collection/source/recovery workspace using the shared Apple storage core. Both native collection prototypes include bounded saved-source search, current-source copy export and native source-menu insertion of emphasis, inline/fenced code and link/image-reference templates with undo. The bundled WebKit fixture and browser shell continue to exercise editor boundaries. Complete rendering, external providers, physical devices, VoiceOver, network isolation and release readiness remain gated.

The publication status is recorded in [docs/github-destination.md](docs/github-destination.md). [The publication review](docs/publication-review.md) explains history privacy cleanup and maps earlier research checkpoint IDs to public commits.

## Reproduce

- Node 22+: `npm ci --ignore-scripts`, then `npm test`.
- Native parser comparison: `cargo run --locked --manifest-path spikes/native-parser/Cargo.toml` (optional `-- --diffs`).
- macOS headless TextKit storage: `swift spikes/native-editor/source-mapping.swift`.
- Headless 1 MB projection measurement: `node scripts/measure-editor.mjs`.
- macOS native collections and separate WebKit research fixture: `spikes/macos-editor/README.md`.
- Native Swift collections, source/reading editing, selection and recovery: `spikes/ios-editor/README.md`.

Use a supported Node.js 22+ installation; verification runs use Node.js 24. The reference/code-block checkpoint passes **123 shared Mac tests and 14 focused AppKit/Transferable groups**, with successful warnings-as-errors Mac and iOS builds. Actual OS menu/input, export picker/provider and iOS runtime validation remain open. The native probe retains a TextKit diagnostic during Link undo/redo despite passing source/selection assertions; the prior iOS recovery-input failure and simulator boot error 22 also remain open. See [reference and code-block insertion](docs/native-markdown-structure-validation.md), [inline Markdown insertion](docs/native-markdown-insertion-validation.md), [source-copy export](docs/native-source-copy-export-validation.md), [saved-source search](docs/native-collection-search-validation.md), and [historical iOS Save As evidence](docs/native-save-as-validation.md).

`docs/adr-0001-grammar-spike.md` through `adr-0005-ios-declarative-fallback.md` document findings and unresolved acceptance gates. Parser fixture HTML is compared only as inert strings and is never rendered. Sandbox code is an authored adversarial test harness, not a production scripting API. The native typed calculator kernel does not parse untrusted document JSON. The revision model is an in-memory protocol experiment, not Firebase rules or cryptography.

Upstream conformance fixtures retain their attribution and CC BY-SA notices in [fixtures/NOTICE.md](fixtures/NOTICE.md). No project-wide open-source license has been selected.
