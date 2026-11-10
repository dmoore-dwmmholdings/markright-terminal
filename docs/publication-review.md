# Public source review — November 10, 2026

Public repository creation was explicitly authorized. The complete 46-commit research history, current source and intended publication were reviewed before upload using a full reachable-blob scan and an independent manual documentation/configuration/metadata review. No credentials or user documents were identified. Build products, screenshots, result bundles, caches, signing assets and local settings remain excluded from the tracked source.

The published research history preserves all 46 changes, messages, timestamps and parent relationships, with new commit IDs. Local-machine paths and unrelated operational coordination were removed from historical documentation; commit metadata uses the confirmed public developer identity and GitHub's ID-based no-reply address. Source code and fixtures are byte-identical to the verified original research checkpoint. The original history and local test evidence remain preserved separately and are not pushed.

Older checkpoint IDs in research notes refer to that original local history. [research-commit-map.json](research-commit-map.json) maps them to public commits. The publication commit adds only public documentation and this map. Fixture corpus hashes still match fixtures/NOTICE.md; upstream CC BY-SA attribution/adaptation notices are retained. No project-wide license is chosen implicitly by publication.

Native recovery checkpoint validation passed **71 native/model/decoder +19 UI** tests (90 total), zero failures/skips/runtime warnings, Swift warnings-as-errors. The owned simulator was restored to Shutdown. Local result bundles and synthetic screenshots remain local; docs/native-recovery-validation.md records reproducible paths and qualification limits. Privacy edits do not modify executable code, fixtures or the validated storage/editor behavior.

Public source availability is not a release, deployment or acceptance claim. Production MRK-18/MRK-12, complete parsing/rendering, external providers, crash-before-checkpoint/power-loss/disk-full, actual filesystem-fault injection, VoiceOver/real keyboard IME, physical devices and security/isolation/release gates remain open.
