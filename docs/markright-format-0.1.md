# Markright format profile 0.1

Status: normative research proposal for MRK-8, subject to integrated MRK-12 review. This defines intended compatibility; it does not assert a production parser/resolver/export implementation exists.

## Identity and baseline

Source is UTF-8. Preserve source bytes, including BOM and LF/CRLF/CR line endings. `.md` is always ordinary Markdown and cannot opt into extensions by containing a marker. `.mrk` without a marker means profile **0.1**, not “whatever the newest runtime supports.” An optional first physical line, after an optional UTF-8 BOM, is exactly `<!-- markright: 0.1 -->`. A malformed or unsupported declared marker keeps source/ordinary Markdown readable but disables extension interpretation and reports a diagnostic. A first-line comment prefix with optional spaces/tabs before `<!--`, optional spaces/tabs before `markright`, and a following space, tab, colon or end-of-line is reserved as a marker candidate; anything other than the exact supported marker fails closed. Markers elsewhere are ordinary source. Future incompatible versions require an explicit supported marker; never reinterpret old versionless files.

Parsing baseline: CommonMark 0.31.2 plus the GFM 0.29 definitions for tables, task lists, strikethrough, extended autolinks and raw-tag filtering. The intended AST includes GFM's bare FTP autolink case. Navigation is a separate permission/URL-policy decision; recognizing an FTP link does not open it. The JavaScript reference's missing FTP case is an explicit MRK-13 adapter/parity gap, not an undocumented language deviation. Comrak currently recognizes it.

Raw HTML is retained as an opaque source node and rendered escaped/inert, never passed to a browser DOM. Thus unsafe normative HTML-string fixtures test parser compatibility only, not the production renderer contract. Renderer output may differ in harmless entity spelling, checkbox attribute ordering or table whitespace; semantic content and source ranges must not differ. The format marker may be presented as metadata but must remain in source/export.

## Lexical contract

Names and keywords are case-sensitive. An identifier is `[A-Za-z][A-Za-z0-9_-]*`. Named data, script and snippet definitions share a document namespace. Duplicate definitions are diagnosed and cannot silently shadow each other; resolution of ambiguous IDs fails locally while preserving both sources.

Attributes are fixed-order in 0.1, separated by one ASCII space, with double-quoted values. There is no backslash escape syntax inside attributes. Literal quotes/control characters/newlines are forbidden; percent-encoding may represent target-path characters, but decoding is the resolver's job. Braces inside quoted values are literal. Values remain exact source strings; Markdown emphasis, links, entities or code spans must never rewrite them. Unknown/duplicate/reordered attributes are invalid, not silently ignored.

Block directives begin at logical column zero, excluding an initial BOM. A directive-looking line inside code, a Markdown container or an enclosing multiline inline construct is not a directive. A recognized directive owns its own attribute bytes even when those bytes resemble inline Markdown. Escaped `\::include` remains ordinary source. Fences follow CommonMark character/length closure rules, including tilde fences and up to three leading spaces. Ordinary fences hide all extension-looking body text.

## Productions

```
file-card = ':file[' label ']{src="' target '"' [ ' display="' ('card'|'inline') '"' ] '}'
include   = '::include{src="' target '"' [ ' headingOffset="' ('0'|'1'|'2'|'3'|'4'|'5') '"' ] '}' trailing-space
snippet   = ':::snippet{id="' identifier '"}' trailing-space newline { body-line newline } ':::' trailing-space
fence-info-data   = 'markright-data id="' identifier '"'
fence-info-script = 'markright-js id="' identifier '"' [ ' inputs="' identifier { ',' identifier } '"' ]
```

`newline` is LF, CRLF or CR. `trailing-space` is zero or more ASCII spaces/tabs. A snippet body has zero or more complete lines, so an opener immediately followed on the next line by its closer is empty. The closer may end at EOF; otherwise its line terminator is preserved. `body-line` is interpreted with the fence/ownership and non-nesting rules below.

`label` is nonempty plain text without a closing bracket, backslash or newline; it is not parsed as rich Markdown. `target` is nonempty and quoted as above. File cards may occur in ordinary inline content, including headings/table cells, but never inside existing code, HTML, links or images, including reference links/images. A label's unrelated Markdown reference definition must not steal the card. Odd preceding backslashes escape the colon; even backslashes do not.

Include targets are opaque syntax. Relative paths resolve against the source document, not the embedding document. `#snippet=identifier` selects a named region; no fragment means the full document. Filesystem grants, URI decoding, traversal/symlink protection, cycle/depth/size limits and origin-aware AST transclusion are mandatory MRK-14/15 implementation work. This syntax grants no file or network access. Heading offsets greater than the supported resulting heading depth diagnose; do not silently clamp.

Snippet regions are non-nesting in 0.1. A body may contain ordinary Markdown and inert data/script fences. The standalone closing marker closes the current region only outside fences/owned inline contexts. Nested/unclosed/duplicate regions preserve original source and report diagnostics; affected regions cannot be resolved as if valid.

Named data fence bodies support **JSON only** in 0.1. Parse RFC 8259 JSON with duplicate-key and size/depth validation before exposure; preserve original numeric tokens and require an explicit exact-integer representation when values exceed the host's safe numeric range. These semantics are MRK-16 work, not performed by the inert scanner. GFM tables remain ordinary document tables. Explicit typed table-to-data declarations and YAML/TOML data fences are reserved, not accepted silently as JSON or exposed by scraping display text.

Script fence bodies are opaque source at format parsing time. They never execute on parse/open/import/sync. Declared input IDs are comma-separated without whitespace. Language/runtime/host API versions and trust/hash validation are separate contracts, completed through MRK-10/12 and implemented in MRK-22–24. Unknown language/runtime versions cannot run. Static readers can always show the source and labeled inert snapshots.

## Errors, ranges and evolution

Unknown directives and syntactically complete invalid extensions produce source-local diagnostics. Source is never discarded, coerced into another target or automatically repaired. Unterminated candidates remain literal/inert; production parsing must attach a diagnostic without swallowing unrelated content. The current scanner is only a research adapter, and production diagnostic completeness remains MRK-13 work. Duplicate/invalid nodes may be retained in a lossless AST, but downstream resolution/execution must refuse affected constructs.

Editor spans use zero-based UTF-16 half-open offsets into the exact source snapshot; line numbers are one-based. Native parser spans may use one-based UTF-8 byte columns/inclusive ends and require explicit validated conversion. Reject mid-scalar byte offsets; preserve unspecified native spans as unmappable. Coordinates belong to an immutable source revision; stale coordinates cannot be applied to a different revision. Diagnostics and flattened output retain original document identity and range provenance.

A major/minor grammar change requires a new profile and conformance fixtures. Hosts may impose stricter resource limits without changing source semantics, but must report limits rather than truncate silently. Missing features always preserve readable source.

## Evidence and downstream map

- `fixtures/commonmark-0.31.2.json`: all 652 baseline examples; attribution/hash in NOTICE.
- `fixtures/gfm-0.29.json`: all 24 extension examples, including explicitly classified parser differences.
- `fixtures/calculator.mrk`: representative inert data/script/snippet/include source.
- `test/format.test.mjs`: version dispatch, unsupported/malformed markers, BOM and quoted braces.
- `test/document.test.mjs`, `scan.test.mjs`, `source-fuzz.test.mjs`: positive/negative grammar ownership, escapes, duplicates, unclosed/invalid constructs, exact source retention and deterministic mixed-syntax coordinates.
- `spikes/native-parser`: comparative CommonMark/GFM and native coordinate evidence.

MRK-12 integrates this profile into the shared architecture. MRK-13 implements a production lossless parser and complete diagnostics; MRK-14 handles file resolution/rename safety; MRK-15 handles transclusion/limits; MRK-16 validates typed JSON/data; MRK-17 implements inert exports. Research completion does not mark MRK-R1–R5 implemented.
