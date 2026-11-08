# ADR 0001 — Extension grammar and compatibility corpus

Status: experimental, MRK-8 in progress. References: MRK-R1–R5, Disegno MRK v2.

## Decision proposal

Target CommonMark 0.31.2 plus the GFM 0.29-gfm extension definitions (tables, strikethrough, task lists and autolinks). Pin parser implementation versions in a lockfile before claiming baseline conformance. `.md` never opts into extension interpretation; `.mrk` does. This lexical prototype does not render Markdown and is not proof of baseline conformance.

Keep parsing, file resolution, transclusion and script execution separate. Source text remains authoritative. A node records UTF-16 code-unit half-open ranges for editor compatibility; adapters must explicitly convert to UTF-8 bytes/native string indices. Lines are one-based. Preserve CRLF bytes, Unicode and unrecognized syntax. Source spans never refer to rendered text.

### Candidate comparison

- Rust pulldown-cmark: useful shared native core and event offset ranges; custom block extensions require a block-aware adapter; Swift bridge needed. Candidate, not selected.
- Rust comrak: CommonMark/GFM AST suited to transclusion; verify byte/source-position mappings and serialization fidelity, native footprint and Swift FFI.
- TypeScript unified/remark + micromark: extension hooks and source positions fit desktop editor, but native iOS cannot use a full web wrapper as its implementation. Useful reference parser, not automatically the shared production core.

Do not choose based on a regex spike. MRK-9/10 and a common fixture run must inform MRK-12's framework freeze. No dependencies installed or framework committed yet.

## Proposed v0.1 grammar

Block directives appear at column zero in the first prototype. They must later be recognized inside parsed Markdown block structure, never as an unrestricted preprocessor. Indented code, escaped directives, ordinary fences and nested quote/list code remain Markdown. Container-context parsing is a known gap of the lexical spike and must gate production.

- `::include{src="relative/path.mrk#snippet=power" headingOffset="1"}`
- `:::snippet{id="power"}` / body / standalone `:::`
- Fenced `markright-data id="register"` with JSON body.
- Fenced `markright-js id="decoder" inputs="register,settings"` with inert script body.
- Typed inline file cards retain the provisional spec form; inline grammar is not implemented by the spike.

IDs use `[A-Za-z][A-Za-z0-9_-]*`, share one namespace per source document, and duplicate definitions diagnose rather than shadow. Double-quoted attribute values only; unknown attributes diagnose. Quoted-value escaping is not yet accepted: use percent-encoded paths, leaving decoding to the resolver. Source paths are not accessed by scanning. A separate resolver validates URI decoding, traversal, root grants and symlink policy. Heading offsets are nonnegative 0–5 in this proposal; resulting depth beyond six must be diagnosed by resolver/rendering rather than silently clamped.

Unknown directive source is preserved and diagnosed. Unclosed extension fences/snippets do not execute or disappear. Scripts are ordinary inert text until a separately qualified host/runtime and local trust consent exist. JSON body schema validation, table typing and duplicate-key policy remain separate work.

## Portability and exports

Flattening is not a lexical replacement. It uses parsed subtrees with source origin, namespaced anchors and cycle/depth/size bounds. Frozen computed output includes input/runtime/source hashes and stale indicators. Script source remains separately available. Export must reject traversal and never implicitly bundle outside-root files.

## Evidence and remaining gates

12 local Node tests initially pass: opt-in isolation, exact CRLF/Unicode offsets, code-fence suppression, escaping/indentation, snippet origin, duplicate IDs, inert script/data, malformed and unknown directives, quotas. These are scanner tests, not CommonMark/GFM or renderer conformance. Next: selected parser fixture adapter, quote/list/fence contexts, inline file grammar and round-trip integration. MRK-8 must remain open until parser comparison is executable, source-map/escaping contracts are frozen and findings are published. No MRK requirement is marked implemented from this slice.

### Executable reference adapter follow-up

Pinned `unified` 11.0.5, `remark-parse` 11.0.0 and `remark-gfm` 4.0.1 with a committed npm lockfile; install scripts disabled. Reference adapter uses parsed root block ownership before extension scanning, excluding ordinary code/list/quote/HTML/table blocks. It never renders HTML, accesses files or executes scripts. Nineteen local tests now pass, including actual GFM AST constructs and container/source-range integration. This resolves the unrestricted top-level scanner's context gap for tested cases, not every CommonMark example. Extension grammar and typed inline cards are still provisional; exhaustive upstream conformance, native parser comparison and source map fuzzing remain incomplete. The raw scanner is internal spike support, not an independently safe Markdown processor.
