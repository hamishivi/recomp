# Verification — Recomp 1.7

**Unsigned native iPhone source. No Xcode SDK build, simulator launch, widget rendering or real-iPhone Health operation was performed.** This report distinguishes executable portable tests from static wiring and untested platform code.

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0. September 18, 2026.

## Actually completed

| Check | Result |
|---|---|
| Portable Swift core, Debug | **286 tests passed, 0 failures** |
| Portable Swift core, Release | **286 tests passed, 0 failures** |
| Production DiaryStore + labelled platform mocks | **134 checks passed** |
| Production MealEstimatorModel + labelled observation/network mocks | **17 checks passed** |
| Node unit/local HTTP suite | **49 tests passed, mocked AI provider** |
| Static feature/project wiring | **93 checks passed** |
| Static interface/assets | **90 checks passed** |
| Retained static DEXA/Health routing | **25 checks passed** |
| App/widget Swift files | **50 files parsed; NOT native SDK type-checked** |
| Scripts/configuration | Python/shell/Node syntax; plist/scheme/project consistency checks passed |
| Independent crypto fixture | Python PBKDF2/AES-GCM round-trip and tag-tamper rejection passed; fixture supplied for native interoperability testing |

Release tests exercise portable core code, not an optimized iOS build. No live AI or external workout-provider request was made. Test records are synthetic and are not bundled into the actual diary. Image framing fixtures do not prove valid native image decoding or vision accuracy.

## What the new executable tests cover

Schema-5 decoding into schema 6; legacy meals without attachments; photo count/size/caption/global budget checks; photo role round trips; evidence bounds; backup payload round trips; preservation of meal/photo/measurement/DEXA IDs and Health receipts; empty-only and matching-bundle restore; connections/widget visibility off after restore; no writes/removals during restore; no replay of acknowledged exports on reconnect; independent context editing/persistence; exact-ID workout deduplication; source filters and local hiding; possible-copy flags without automatic deletion; sleep interval union, single-source selection, clipping and daylight-saving handling; missing step coverage; context validation; private/local-only/date-aware widget snapshots; pure hypothetical food arithmetic; photo refinement requests/locks/failure/cancellation and local retention; request-field isolation and six-image server inputs.

The coordinator tests use a **mock Health adapter**. They establish the coordinator's programmed control flow, not Apple's actual authorization, sample identity, replacement or deletion behaviour. The estimator harness uses a **mock provider**. It does not prove that the AI reads labels correctly. All model outputs remain estimates requiring review.

## Native cryptography remains unverified

`BackupCrypto.swift` calls Apple's CryptoKit, CommonCrypto and Security libraries. Those APIs are unavailable in this Linux test environment. Portable tests validate the payload/envelope/restore rules, not execution of native encryption. The independent Python fixture is not a substitute for the native check.

Run **`./scripts/check-backup-mac.sh`** on macOS. It compiles the exact native implementation, checks interoperability against the synthetic fixture, tests encrypt/decrypt round trips, checks distinct ciphertext on repeated encryption, and rejects wrong passwords and changed salt/tag. This script was supplied but **not run here**. No security audit, secure-memory guarantee or large-file performance certification is claimed.

## Still not verified

- Native SwiftUI/UIKit/HealthKit/WidgetKit/CommonCrypto/CryptoKit compilation or runtime.
- App Group registration/signing, app-extension embedding on a phone, Home Screen previews, tap routing, privacy redaction while locked, midnight refresh timing and group-file protection.
- Camera/photo selection and image decoding, real label extraction, live AI estimates, HTTPS deployment or API billing.
- Native backup Files import/export, wrong-password UI, real encrypted-file restore, practical memory limits and physical-device upgrades.
- Strava/Strong actually writing the selected workouts into a test device's Health store; denied/partial read permission; mixed-source steps/sleep; exact Apple query aggregation or duplicate heuristics on real data.
- Real Health export/replacement/removal after backup restoration, including older backup/newer Health divergence.
- Clinical accuracy of maintenance estimates, body-fat readings or calorie recommendations. Activity notes do not change the equation or prescribe calorie changes.
- Dynamic Type/VoiceOver/layout on Apple hardware, App Review or production security/compliance.

## On-Mac / iPhone acceptance

1. Configure the SAME registered App Group and team for the app and widget. Keep the existing app bundle identifier. Run `./scripts/check.sh`, which runs the native backup harness and builds the app/embedded widget on a Mac with Xcode. Build Debug and Release in Xcode before distribution.
2. In a throwaway test diary, check text/manual values, six-photo estimation, evidence roles, manual locks, failure/undo and attached-photo reopening. Closing Check must create no diary entry, confirmation or Health export.
3. Encrypt/export a synthetic diary, verify the file and password, and restore it into an empty test installation with the same ID. Check meals, PDFs, photos, scale tags and receipts. Wrong passwords/corrupt files/mismatched app IDs/nonempty destinations must leave state unchanged.
4. Reconnect integrations deliberately and inspect updates/deletions. Do not assume an old receipt proves that a matching Health sample still exists. Never run synthetic-write tests against your personal Health store.
5. Connect Strava and Strong to Health, then Recomp's read-only activity view. Test limited permissions, missing history, two workout writers, source selection/hiding/restoring, stage overlap, DST and pauses. Confirm no workout writes or automatic exercise-calorie allowance.
6. Add small/medium widgets. Test numbers off/on, app-versus-system appearance, local-only label, background/lock behaviour, next-day/time-zone invalidation and Log/Check/Weigh links. Check that no link saves immediately.
7. Test a same-ID update over an older installation after retaining an independent copy of its records. No real-device migration was tested for this release.

Historical reports/logs remain under Historical-v1.6 and earlier folders. They are not new platform test evidence. The included macOS GitHub Actions workflow was not run for this delivery.
