# CommonMark fixture provenance

`commonmark-0.31.2.json` is the test corpus from https://spec.commonmark.org/0.31.2/spec.json, downloaded November 8, 2026. SHA-256: d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20.

CommonMark specification by John MacFarlane and contributors, licensed Creative Commons Attribution-ShareAlike 4.0 International: https://creativecommons.org/licenses/by-sa/4.0/ . Specification license and provenance: https://spec.commonmark.org/0.31.2/ . The corpus is preserved unmodified.

The normative compiler comparison permits raw HTML/URL output as inert strings only. This is not the application renderer or an authorization to execute such content. Production sanitization must be tested separately.

## Authored declarative calculator vectors

`bitfields-0.1.json` is authored project test data for the bounded `markright.bitfields/0.1` research profile. It is shared by the JavaScript adapter and native Swift feasibility tests. Expected integer/table values are explicit test expectations. The fixture is trusted test-only input, not an imported document or proof of untrusted JSON validation. Native typed-kernel parity does not cover JavaScript parser-only rules such as duplicate JSON keys, unknown object fields or numeric-token rounding; those retain separate tests and implementation gates.

## GFM extension subset

`gfm-0.29.json` contains all 24 examples from the five GFM extension sections of GitHub's GFM 0.29 specification (672 examples including base Markdown). Source pinned to https://github.com/github/cmark-gfm/blob/27d942c8b0a62d192f616e5bf3578f4b6a89e180/test/spec.txt . Attribution: John MacFarlane and contributors, GitHub. License CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/ . Adaptation: examples extracted into JSON, tab arrows converted to tabs, surrounding prose omitted, original full-corpus example numbers preserved. Derived fixture remains CC BY-SA 4.0. SHA-256 `f8c86c85c691c35bd1816ffd5ea522f1e1ba19b3ae1be340d832e95571909d02`.
