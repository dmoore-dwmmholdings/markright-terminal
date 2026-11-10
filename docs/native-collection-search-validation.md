# MRK-40 native saved-source search

This research slice adds explicit search within the selected app-owned collection on the native macOS and iOS prototypes. It relates to pinned MRK v2 R6/R9/R14/R15. It does not accept complete authoring, indexed search/backlinks, external folder grants, production clients or release readiness.

## User workflow

Expand **Search saved documents**, enter literal text and choose **Search**. The panel is closed by default and never starts a search merely because it appears or the query changes. Results show filenames, bounded plain-source previews and match counts. Errors and omitted work remain visible. Cancel stops the request; changing the query or collection invalidates its results. Opening a result uses the existing guarded fresh-open path: a newly opened document starts at the beginning, while the existing macOS session retains its current position. Results do not jump to an earlier source range.

Only saved source is searched. Unsaved edits and recovery journals are not included. A search neither flushes nor changes the active session. Each document read is a separate snapshot; concurrent saves or outside edits may change files before they are opened from a result. Search does not establish an atomic collection snapshot or external-writer coordination.

The query has its own native text view, with smart punctuation, automatic corrections and rich/link/data handling disabled where available. It requests no focus, shares no field editor, and reads or writes no pasteboard or search history. Equal-byte updates retain the query caret; marked text is not replaced. Search and Clear pause during composition. Return remains literal text; the Search button starts the operation. Native keyboard/IME and accessibility acceptance remain platform-specific gates.

## Read and result boundaries

Matching uses case-insensitive NSString comparison with a fixed POSIX locale and canonical Unicode equivalence. Regular-expression syntax has no special meaning. Matches are nonoverlapping, source bytes are never normalized or rewritten, and previews are displayed verbatim. Each preview begins at the first match, contains at most 160 UTF-16 units plus an ellipsis, and avoids cutting a surrogate pair or CRLF boundary.

Default hard ceilings are 64 attempted document opens, an 8 MiB source-read budget, 50 matching files, 100 counted matches per file and a 256 UTF-16-unit query. A per-file extra-match probe distinguishes an exact count from an omitted remainder. Invalid queries are rejected before filesystem access. Limit settings are clamped to their hard ceilings and negative values to zero.

Before every source open, the engine requires enough remaining budget to reserve the store's maximum 1 MiB document. Successful reads charge their actual baseline byte count; failed reads conservatively charge the full reservation because the bytes read are unknown. The displayed budget therefore includes failed-read reservations. This may stop before all nominal bytes are used. File, result and match limits are reported when work was omitted; a partial scan is never described as a complete no-match result.

All enumeration and reads use the existing CollectionStore path, exact-name, hardlink, UTF-8 and size checks, with root creation explicitly disabled. Missing or deleted roots are not recreated. Existing non-search callers retain their default root-creation behavior. An unsafe inventory entry refuses enumeration; individual read failures are reported while other eligible files continue within the bounds. Linked assets, includes, hidden metadata and other collections are not opened as search source. No index, cache, diagnostic upload, script execution or network capability is added.

Cancellation is checked before enumeration, between files and matches, and before returning. The actor yields between file reads so other storage work can progress. A request token and byte-exact input checks prevent an older completion or error from replacing a newer query's state. Result actions also validate their captured result against the current report and live collection before opening a document.

## Evidence and remaining gates

The shared Mac corpus passes **90 tests**, zero failures, with Swift warnings as errors: `spikes/macos-editor/build/MRK40-shared-core-macos-final-20261110.log`. This includes 20 real-store search groups and 12 controlled asynchronous state/result-action groups, alongside the prior 58 storage/session tests. The first compile diagnostic in a test weak-reference cleanup was corrected; its log is preserved.

The initial offscreen AppKit run passes the prior five groups and the new literal-query group, then times out checking literal preview text in the local accessibility tree. The traversal previously admitted only two concrete classes; it has been expanded to public accessibility objects/proxies without weakening the text expectation. The corrected probe, source-retention group, final native builds and iOS compile await the coordinated validation slot. No current eight-group pass is claimed. A Mac app candidate build passes in `MRK40-native-macos-build-20261110.log`; the final Verification product still needs rebuilding after the result-action guard.

Generated products, synthetic fixtures, failed/passing logs and result bundles stay ignored locally. Builds require at least 20 GiB free and use owned resources with bounded parallelism. The visible Debug app and bundled WebKit fixture remain separate from the unused Verification product.

The existing iOS recovery-input failure and simulator boot error 22 remain unresolved. Shared Mac tests and an iOS compilation do not qualify the iOS search interaction, OS keyboard/IME, VoiceOver, physical devices or complete rendering. Network/process isolation, ingestion, external providers, portability/identity and release gates remain open.
