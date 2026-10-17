# Verification — Recomp 1.3 scale/location update

**Unsigned Xcode source project. Not compiled against Apple's iOS SDK or run on an iPhone.**

## Checks actually completed

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0; September 18, 2026.

| Check | Result |
|---|---|
| Portable Swift package, Debug | **168 passed, 0 failures** (136 retained + 32 scale/location tests) |
| Portable Swift package, Release | **168 passed, 0 failures** |
| Production DiaryStore against explicit portable test doubles | **47 coordinator checks passed** (21 retained + 26 new) |
| Node provider/unit/local HTTP tests | **42 passed, 0 failures**, mocked AI provider; no live AI request |
| All 28 app Swift files, parser only | Passed; **not native SDK type checking** |
| Xcode source membership, Info/entitlement/privacy plist, scheme XML | Consistency checks passed; version 1.3, build 4 |
| Node, shell and Python syntax; executable script permissions | Passed |

Logs: `core-tests.log`, `release-core-tests.log`, `store-checks.log`, `server-tests.log`, `source-checks.log`, `full-check.log`.

The Release compile required a retry after a command timeout; the retained Release log records a completed 168-test pass. No native build is inferred from that result.

## New coverage

- Physical-scale IDs, Home/Girlfriend’s defaults without invented measurements, valid/unique labels, archived references and unknown-ID rejection.
- Schema-2 migration retaining old untagged readings and receipts; schema-1 compatibility retained; schema-3 round trips including local Health annotations and scale selection.
- Per-scale daily medians and curves; no cross-scale chart averaging; one coverage day for multiple scales on the same day; excluded entries and body-fat method separation.
- Source-aware deduplication of own exports; local tagging of imported samples without copying or exporting third-party data; restart/re-read persistence and clearing annotations.
- Constant-offset invariance with daily or weekly alternating scale visits; preserved common loss/gain slopes; selectable single-scale estimates without fallback; untagged-data policy; rejection of one-off, sparse and disconnected histories; conflicting-scale trend suppression.
- Scale/location separation for waist comparisons; body-fat values remain absent from calorie estimates; deterministic input order; CSV labels, stable IDs and formula escaping.
- Production coordinator: new-entry defaults, retagging existing IDs, old-history edits not changing defaults, renaming, archive retention/default clearing, maintenance selection, import annotation and persistence.

The coordinator harness compiles the production DiaryStore with labelled mock Combine/HealthKit adapters. It checks Swift typing, local persistence and control flow—not Apple's permissions, sync replacement/deletion semantics, framework behaviour or UI rendering. The source parser checks Swift syntax only.

## Still unverified

- Native SwiftUI/Charts/UIKit/HealthKit/PhotosUI/AVFoundation/Security compilation, simulator launch, signing, physical-device installation and upgrade.
- Picker, navigation, sheets, charts, labels, accessibility, long text, unit switching and real-device layout/performance.
- Actual Health read/write permissions, own-sample replacement after tag edits, true imported-sample annotation/reread behaviour and tag retention across a device upgrade.
- Camera/photo workflow, live AI estimates, service hosting, live billing and Mac GitHub Actions.
- Real-world accuracy, scale calibration/drift, fitness suitability or clinical validation of the maintenance method.

Tests verify the programmed rules on synthetic data. They do not establish measurement accuracy or prove that two real scales have constant offsets. Guidance remains opt-in and review-before-apply.

## Native acceptance checklist

1. On a Mac with Xcode, run `./scripts/check.sh`; build Debug and Release for simulator and phone.
2. Update without uninstalling, using the same bundle ID/team. Export first. Check existing food/AI data, measurements, targets and sync queues; existing readings must remain untagged.
3. Log a Home check-in with weight and body fat. Open another: Home should be preselected. Change to Girlfriend’s, save, and check its next-entry default. Edit old history and ensure that does not change the default.
4. Add/rename/archive/restore a custom scale. Verify historical references stay intact, archived defaults clear, and archived scales remain filterable. Try invalid/duplicate names.
5. Tag and untag local and imported readings. Imports should remain one reading and should not trigger a Health write. Reopen the app and refresh Health to verify the annotation remains for the same sample ID.
6. Inspect Body and Trends with all-scales, one-scale and untagged filters. Curves and rolling averages must never combine scales. Verify body-fat/tape method separation and kg/lb display.
7. Use the read-only Two scales, different baselines demo. Confirm it writes nothing to the diary/Health and shows flat synthetic weight trend despite alternating baselines.
8. Use a controlled test diary to inspect automatic within-scale and single-scale estimates, incomplete/sparse/untagged warnings, and conflicting-scale proposal suppression. Existing Apply/cooldown safeguards must remain.
9. Edit a locally exported tag and check Health replaces the same numeric measurement rather than adding another; imported annotation must never alter Health. Verify no location metadata/GPS permission is added.
10. Export local measurements and analysis CSVs; check tags/IDs, archived labels, formula escaping and new snapshot scale context. CSV remains an export, not a restore mechanism.

The old v1.2 status is retained separately as `V1_2_HISTORICAL_STATUS.md`; its counts are historical, not this delivery's verification.
