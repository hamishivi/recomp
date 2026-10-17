# Third audit — September 25, 2026

## Fixes

- **Concurrent food/body edits:** different payloads at the same record version now reject the merge, preserving the active diary and showing a resolution message. A newer Health export timestamp no longer chooses which food content wins. Identical payloads combine their Health export receipts. Re-saving the intended record on one device advances its version before retrying sync.
- **Deleted records returning from stale devices:** durable deletion identities are now separate from transient Health cleanup queues. Food, body measurements (including metrics not supported by Health), food templates, context events and DXA scans stay deleted after cleanup and subsequent merges. Receiving a deletion queues local Health cleanup where needed, including deselecting previously exported DXA metrics. Stale own-app Health nutrition/body samples are filtered using durable identities.
- **Removed food confirmations returning:** unconfirming, removing coverage or invalidating a review records its removal time. Older peer confirmations cannot restore it; a later explicit confirmation can. The newest confirmation wins; different confirmations at an identical timestamp reject the merge. This protects the intake evidence used by maintenance estimation.
- **Storage selection:** without an explicit storage preference, an existing local diary takes priority when iCloud becomes available. Explicit preferences remain respected, and an existing cloud diary can still be found when no local diary exists.
- **Stale confirmation checkbox:** the “all food and drinks are included” checkbox resets when the displayed totals, selected day or inclusion of additional Health nutrition changes.

## Compatibility and migration

Diary format is now **8**. Formats 1–7 migrate automatically on load, with an atomic save after validation. Existing pending food/body deletions and deleted-scan cleanup links become durable deletion records. Older app versions reject the new format instead of silently dropping its protection. Backup round trips retain the new metadata.

The encrypted Wi-Fi service and authenticated-data namespace were advanced together. **Update both devices before syncing.** The pairing-code workflow is unchanged. Old encrypted peers are intentionally not discovered by the new service.

Deletion records whose identities were already forgotten by older versions cannot be reconstructed during migration. The protection applies to retained deletion queues and future deletions. Durable records are retained rather than pruned without evidence that every peer has received them. Each collection has a validation limit of 100,000 deletion identities.

Review ordering uses device timestamps, so materially incorrect device clocks can affect reconfirmation ordering. Unversioned template/context/scale/DXA edit conflicts still use the existing merge rules; this pass adds durable deletion handling for those records rather than introducing an edit-history system.

## Verification

Regression coverage includes equal-version conflict rejection in both directions, receipt combination, durable deletion round trips and stale-peer merges, migration from format 7, malformed deletion metadata, review removal/reconfirmation, DXA cleanup, non-Health body measurements and storage selection. The real-store audit exercises save → Health export → delete → Health cleanup → stale merge, and checks that a stale Health sample cannot inflate calories after cleanup.

Completed portable verification:

- 429 core tests in both Debug and Release.
- 38 persistence audit checks, plus all existing coordinator, source-contract and network harnesses.
- 68 server tests.
- Production encrypted loopback sync checks for matching/wrong codes and cancelled transfers.

Native verification:

- 434 native unit tests and all 13 UI tests passed with Xcode 27.0 / iOS 27.0 Simulator.
- Release app/widget build succeeded; the complete `scripts/check.sh` pipeline exited 0.

Xcode's optional simulator diagnostics collector stopped making visible progress after the tests completed. Only that collector was terminated; Xcode then reported TEST SUCCEEDED and proceeded to the Release build. Some optional diagnostics may be absent.

Logs: [verification directory](../../Verification/Third-Audit-2026-09-25/). Native result bundle: `.native-results/20260925-211405-48959/Tests.xcresult`.

Bonjour discovery and physical-device exchange remain unverified. Previous audits recorded transient “Invalid frame dimension” warnings in food-sheet transitions; this pass does not claim to resolve those layout warnings.
