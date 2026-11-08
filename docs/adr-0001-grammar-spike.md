# ADR 0001 — Extension grammar and compatibility corpus

Status: experimental, MRK-8 in progress. References: MRK-R1–R5, Disegno MRK v2.

## Decision proposal

Target CommonMark 0.31.2 plus the GFM 0.29-gfm extension definitions (tables, strikethrough, task lists and autolinks). Pin parser implementation versions in a lockfile before claiming baseline conformance. `.md` never opts into extension interpretation; `.mrk` does. This lexical prototype does not render Markdown and is not proof of baseline conformance.

Keep parsing, file resolution, transclusion and script execution separate. Source text remains authoritative. A node records UTF-16 code-unit half-open ranges for editor compatibility; adapters must explicitly convert to UTF-8 bytes/native string indices. Lines are one-based. Preserve CRLF bytes, Unicode and unrecognized syntax. Source spans never refer to rendered text.

### Candidate comparison

- Rust pulldown-cmark: useful shared native core and event offset ranges; custom block extensions require a block-aware adapter; Swift bridge needed. Candidate, not selected.
- Rust comrak: CommonMark/GFM AST suited to transclusion; verify byte/source-position mappings and serialization fidelity, native footprint and Swift FFI.
- TypeScript unified/remark + micromark: extension hooks and source positions fit desktop editor, but native iOS cannot use a full web wrapper as its implementation. Useful reference parser, not automatically the shared production core.

Do not choose based on a regex spike. MRK-9/10 and a common fixture run must inform MRK-12's framework freeze. Pinned reference dependencies have now been installed; no production framework is committed.

## Proposed v0.1 grammar

Block directives appear at column zero in the first prototype. They must later be recognized inside parsed Markdown block structure, never as an unrestricted preprocessor. Indented code, escaped directives, ordinary fences and nested quote/list code remain Markdown. Container-context parsing is a known gap of the lexical spike and must gate production.

- `::include{src="relative/path.mrk#snippet=power" headingOffset="1"}`
- `:::snippet{id="power"}` / body / standalone `:::`
- Fenced `markright-data id="register"` with JSON body.
- Fenced `markright-js id="decoder" inputs="register,settings"` with inert script body.
- Typed inline file cards use the provisional spec form; see the source-mapped checkpoint below.

IDs use `[A-Za-z][A-Za-z0-9_-]*`, share one namespace per source document, and duplicate definitions diagnose rather than shadow. Double-quoted attribute values only; unknown attributes diagnose. Quoted-value escaping is not yet accepted: use percent-encoded paths, leaving decoding to the resolver. Source paths are not accessed by scanning. A separate resolver validates URI decoding, traversal, root grants and symlink policy. Heading offsets are nonnegative 0–5 in this proposal; resulting depth beyond six must be diagnosed by resolver/rendering rather than silently clamped.

Unknown directive source is preserved and diagnosed. Unclosed extension fences/snippets do not execute or disappear. Scripts are ordinary inert text until a separately qualified host/runtime and local trust consent exist. JSON body schema validation, table typing and duplicate-key policy remain separate work.

## Portability and exports

Flattening is not a lexical replacement. It uses parsed subtrees with source origin, namespaced anchors and cycle/depth/size bounds. Frozen computed output includes input/runtime/source hashes and stale indicators. Script source remains separately available. Export must reject traversal and never implicitly bundle outside-root files.

## Evidence and remaining gates

12 local Node tests initially pass: opt-in isolation, exact CRLF/Unicode offsets, code-fence suppression, escaping/indentation, snippet origin, duplicate IDs, inert script/data, malformed and unknown directives, quotas. These are scanner tests, not CommonMark/GFM or renderer conformance. Next: selected parser fixture adapter, quote/list/fence contexts, inline file grammar and round-trip integration. MRK-8 must remain open until parser comparison is executable, source-map/escaping contracts are frozen and findings are published. No MRK requirement is marked implemented from this slice.

### Executable reference adapter follow-up

Pinned `unified` 11.0.5, `remark-parse` 11.0.0 and `remark-gfm` 4.0.1 with a committed npm lockfile; install scripts disabled. Reference adapter uses parsed root block ownership before extension scanning, excluding ordinary code/list/quote/HTML/table blocks. It never renders HTML, accesses files or executes scripts. Nineteen local tests now pass, including actual GFM AST constructs and container/source-range integration. This resolves the unrestricted top-level scanner's context gap for tested cases, not every CommonMark example. Extension grammar and typed inline cards are still provisional; exhaustive upstream conformance, native parser comparison and source map fuzzing remain incomplete. The raw scanner is internal spike support, not an independently safe Markdown processor.

### CommonMark corpus qualification

The pinned micromark 4.0.3 reference compiler passes all 652 upstream CommonMark 0.31.2 examples exactly as HTML strings. Every source also passes extension-opaque `.md` parsing and AST range checks. Normative fixture-only comparison allows raw HTML/URLs as strings and never renders them; production safe output remains separate. Corpus hash/license provenance is recorded in fixtures/NOTICE.md. Twenty-one test groups pass on the Mac. This validates the selected JavaScript reference baseline, not Rust/Swift parity or every GFM extension example.

### Typed-file reference checkpoint

The reference adapter now recognizes proposed inline `:file[label]{src="./path" display="card"}` syntax in Markdown text nodes. `display` may be `card` or `inline` (default `card`). Labels in this initial grammar are nonempty plain text without escapes; attributes are deliberately strict. Code, HTML, existing links, and images cannot contain active file cards. Odd-backslash escapes are preserved; no file is opened and no URL is fetched. These nodes are syntax records only, not safe/resolved file references. Path confinement, symlinks, URI schemes, filesystem capabilities, and native parser parity remain implementation gates.

Line positions use a single line-start index and binary search rather than rescanning every source prefix. The 2,000-card CRLF fixture verifies every source slice and line. Current evidence: 25 passing test groups, including all 652 upstream CommonMark examples. This is still an experimental grammar spike, not an implemented renderer or shipped language contract.


### Native parser comparison

`cargo run --locked --manifest-path spikes/native-parser/Cargo.toml` repeats the same 652 CommonMark examples using pinned pulldown-cmark 0.13.6, with optional `-- --diffs` for inert JSON diagnostic output. All event ranges are checked as bounded UTF-8 byte offsets at character boundaries. It produces 630 exact HTML-string matches. Inspection of the 22 differences shows 21 quote-serialization variants (`"` versus `&quot;` in text) and one newline formatting difference before a raw HTML block in a list (example 175). These are not evidence of 22 Markdown interpretation defects. No blanket normalization has been applied: exact expected difference IDs are checked to detect drift. Production rendering still requires sanitization independently.

The parser provides useful byte ranges, but converting them to native editor positions, matching GFM behavior, handling extension ASTs, comparing comrak, and validating Swift integration remain gates. This evidence supports retaining pulldown-cmark as a candidate rather than selecting the final core. Cargo lockfile is committed; no production runtime added.

### Cross-parser GFM findings

Pinned comrak 0.59.0 passes all 652 CommonMark examples exactly. The 24 GFM extension examples are separately pinned to cmark-gfm commit 27d942c8; base CommonMark remains 0.31.2 rather than silently reverting to GFM's older baseline. Both Rust candidates and micromark now run that subset. Exact known-difference lists are regression assertions, not claims of complete conformance.

- micromark GFM: 21/24 exact. Two checkbox serialization differences; one genuine policy difference: no bare `ftp://` autolinking (example 628).
- comrak: 21/24 exact. Two checkbox serialization differences; raw HTML tag filtering differs in the deliberately unsafe fixture comparison mode (652). This is not a production safe-render configuration.
- pulldown-cmark: 3/24 exact. Table/checkbox serialization contributes differences, but bare GFM autolinks are absent, including www, HTTP and email examples, and raw tag filtering differs. `ENABLE_GFM` does not supply complete GFM support by itself.

Tentative preference is comrak for a native AST candidate, pending native range mapping and Swift/UI measurements. Do not choose pulldown merely for ranges without budgeting missing autolink behavior. Define whether bare FTP links are supported in the frozen Markright contract; do not let JavaScript/native disagreement silently decide it. Regardless of parser, production HTML is not passed through: use safe native/render nodes and explicit URL policy. No renderer security assurance follows from these string tests.

### Source ownership hardening

Self-review found two gaps not caught by the initial corpus: column-zero directive text inside multiline inline-code/emphasis/link spans could be misread as a block directive, and standalone CR lines did not share CommonMark's line-ending handling. The adapter now masks inline-owned ranges for block scanning; scanner, file-node locations and editor indexes support LF, CRLF and CR without normalization. Regression tests plus a 200-case deterministic mixed Unicode/Markdown/directive corpus check source preservation and bounded coordinates. These checks improve safety but are not exhaustive fuzzing or independent review.

### Native source-map evidence

`cargo test --locked --manifest-path spikes/native-parser/Cargo.toml` now verifies three mapping probes. Comrak uses one-based UTF-8 byte columns with inclusive end positions; the editor contract uses zero-based UTF-16 half-open ranges. Unicode strong-span fixtures round-trip across LF, CRLF and CR, and mid-scalar byte positions are rejected rather than rounded. Auditing all CommonMark fixtures maps 3,301 native AST spans to bounded scalar-aligned source ranges; six spans have unspecified/zero positions and must remain explicitly unmappable, not be guessed. This validates coordinate arithmetic for the pinned corpus, not source identity after edits or a Swift FFI implementation.

### Independent review corrections

Review reproduced a serious masked-source defect: emphasis/backticks inside quoted include paths could silently change the emitted path. The scanner adapter now restores exact bytes of candidate directive lines only when the line start is not owned by another container/inline construct. File cards are scanned from original paragraph/heading/table-cell spans rather than individual Markdown text nodes, while rejecting starts inside code, HTML, links or images. This preserves URLs and Markdown punctuation inside attributes and prevents an unrelated reference-link definition from stealing a card's label. Regression tests cover each reviewer reproduction. Source ownership remains a grammar-spike area requiring review, never a reason to resolve a changed path silently.
