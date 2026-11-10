# Markright Terminal

Local feasibility workspace for Disegno MRK v2, Andare MRK-8 through MRK-11. This is not a shipped application or frozen language contract. No document is automatically evaluated. No Firebase service or remote repository was created by this work.

The current GitHub destination check and exact push blocker are recorded in [docs/github-destination.md](docs/github-destination.md). Local commits remain available; no remote target is guessed.

## Reproduce

- Node 22+: `npm ci --ignore-scripts`, then `npm test`.
- Native parser comparison: `cargo run --locked --manifest-path spikes/native-parser/Cargo.toml` (optional `-- --diffs`).
- macOS headless TextKit storage: `swift spikes/native-editor/source-mapping.swift`.
- Headless 1 MB projection measurement: `node scripts/measure-editor.mjs`.
- Standalone macOS WebKit research app: build instructions and exact limitations in `spikes/macos-editor/README.md`.
- Native Swift interaction, source/reading modes and selection continuity: `spikes/ios-editor/README.md`.

Use a supported Node.js 22+ installation; verification runs use Node.js 24.

`docs/adr-0001-grammar-spike.md` through `adr-0005-ios-declarative-fallback.md` document findings and unresolved acceptance gates. Parser fixture HTML is compared only as inert strings and is never rendered. Sandbox code is an authored adversarial test harness, not a production scripting API. The native typed calculator kernel does not parse untrusted document JSON. The revision model is an in-memory protocol experiment, not Firebase rules or cryptography.
