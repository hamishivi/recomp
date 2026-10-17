# Recomp 1.10 — verification

**Source update, not a verified native iPhone build.** Tested on Linux x86_64 with Swift 6.2.1 and Node.js 22.16.0, September 18, 2026 (Los Angeles). No Xcode, Apple SDK, simulator, live API key, camera or personal Health store was used. The user's earlier Xcode run does not establish that this revised interface compiles or renders correctly.

Version **1.10 / build 14 / diary schema 7**. Input: `Recomp-Startup-Fixes-v1.9.1.zip`. The in-place patch also accepts the original v1.9 source and includes the v1.9.1 startup fixes.

## Implemented

- Remove the app-name home heading; keep the native date selector in the navigation bar.
- Replace the calorie ruler/macro table with four solid concentric rings plus labelled numeric totals, targets and remaining/over values. Rings clamp visual progress only; food data is not clamped. Reduce Motion disables ring interpolation.
- Replace numbered section badges with sentence-case headings, spacing and panel borders across the interface.
- Route Log food, editing and widget logging through the same native form. Photos, saved foods, manual values and optional AI estimation share one draft and Save action.
- Keep Check food unsaved until an explicit change to logging followed by Save.
- Move Your usuals into food entry and a searchable Settings submenu. Selecting a usual fills the draft; replacing nonzero food asks first.
- Shorten visible copy and move supplementary Health/privacy details behind native disclosure/navigation. Consent, API charges, permissions, data loss and travel caveats remain.

## Executed checks

| Check | Result | Scope |
|---|---:|---|
| Full portable gate | **Exit 0** | Actual final models and existing integration harnesses; prints native limitation explicitly |
| Swift core, Debug | **384 passed, 0 failures** | 374 retained tests and 10 ring-display tests |
| Swift core, Release | **384 passed, 0 failures** | Optimized Linux code, not an iOS Release build |
| New unified food composer | **43 checks passed** | Actual MealEstimatorModel, DiaryStore and filesystem; mocked observation, Health and AI |
| Existing DiaryStore | **134 checks passed** | Production coordinator, fake Health |
| Existing meal estimator | **17 checks passed** | Production model, fake network/observation |
| Startup coordinator | **8 checks passed** | Earlier startup/persistence regressions |
| Retained audit harnesses | **20 / 17 checks passed** | Existing state-management, pause, correction and sync races |
| Travel coordinator | **36 checks plus 7 process runs passed** | Linux timezone/relaunch and filesystem, fake Health |
| Proxy-route HTTP client | **24 checks passed** | Production client against localhost synthetic responses |
| Direct-route HTTP client | **25 checks passed** | Fixed-endpoint request contract with localhost rerouting; no OpenAI request |
| Optional Node server | **65 tests passed** | Fake upstream provider; server source unchanged |
| New UI source/contrast checks | **39 passed** | Selected routing, labels, rings and arc/track contrast; not rendered UI |
| Retained interface / feature / DEXA wiring | **96 / 99 / 25 passed** | Static source, asset and project checks |
| In-place patch | **23 checks passed** | Temporary v1.9 and v1.9.1 copies with custom signing identifiers |
| Swift syntax | **58 files parsed** | App, widget, UI tests and native crypto tests; not Apple SDK type-checking |
| Configuration | **Passed** | Plists, entitlements, privacy manifests, asset JSON, scheme XML, OpenStep project and script syntax |
| Native gate attempt | **Unavailable, exit 2** | Xcode/macOS missing; NOT a passed native test |

The gate's current log is `Verification/UI-1.10/full-gate.log` with `full-gate.exit = 0`. Final cosmetic footer/disclosure text was shortened after that run; those files were parsed again and the affected static checks rerun on the final source. No runtime logic changed after the gate.

Repeated Debug/Release runs are not additional unique tests. The ten new ring methods include 2,000 seeded numerical scenarios, not 2,000 extra XCTest methods. There was **no new AddressSanitizer run** for this version. Earlier sanitizer logs describe earlier releases.

## What the new checks cover

Composer cases cover manual values with no AI setup; attaching photos without sending them; reopening retained photos; keeping an edited meal's original identity; saving/reloading through the actual store; saved-food selection without persistence; metadata/clock/photo preservation on replacement; invalid numeric input blocking save and AI; exact scaling; manual totals protected during refinement; large valid local values that cannot fit the AI schema; bounds and duplicate photos; first requests using food name and details; AI success/failure/cancellation; no diary write from Check; undo; and correct default estimate status from an empty home-screen seed.

The ring helper is tested for zero, exact and over-target intake, invalid/missing targets, nonfinite/overflow inputs, preserved input data and bounded proportions. This tests arithmetic, not visual spacing, color rendering or VoiceOver execution.

The patch checks dry-run nonmutation, both supported starting releases, payload/source hashes, custom bundle IDs/teams/App Groups and unchanged schemes, custom plist keys, version updates, source backups, repeat no-op application, unexpected-source refusal, corrupt payload refusal, wrong-folder guidance, symlink refusal and rollback after a simulated second-write failure. Patch tests do not access a phone or diary. Source rollback is not a full filesystem transaction and is not a diary backup.

## Preserved code

Compared with v1.9.1, all original Core files are byte-identical except `DiaryMath.swift`, whose original contents remain byte-identical with the pure ring-display helper appended. All Services files are byte-identical except `MealEstimatorModel.swift`. Server files are byte-identical. Thus no Health adapter, maintenance equation, DEXA mapping, backup cryptography, HTTP transport or API contract was rewritten in this update.

Native view wiring and the unified editor did change. Existing portable tests cannot prove those SwiftUI bindings and lifecycle callbacks work correctly on iPhone.

## Evidence

- `Verification/UI-1.10/full-gate.log` / `.exit`: final model/core/harness/HTTP/server run.
- `Verification/UI-1.10/composer.log`: earlier 42-check development run; the gate includes the final additional blank-seed regression and 43 checks.
- `Verification/UI-1.10/final-source-checks.log`: final parsing, static checks, assets, project syntax and unchanged-domain-code comparisons.
- `Verification/UI-1.10/patch.log`: 23 isolated-copy update checks.
- `Verification/UI-1.10/native-attempt.log`: explicit unavailable-native result.

Historical verification directories remain historical; they are not new native evidence.

## On your Mac / iPhone — still required

Apply the patch with Xcode closed, then run from the project root:

```bash
./scripts/check-native.sh
```

This creates a disposable simulator and runs the native core/crypto/UI tests plus a Release app/widget build. New UI cases exercise the single Log food path, photo controls on new/existing entries, selecting a usual without logging, cancelling changed drafts, Check isolation and the Settings submenu. These UI cases were **added but not executed here**.

After it builds, check small-screen and large-text layouts, light/dark/increased contrast, VoiceOver and Reduce Motion, over-target readouts, actual photo selection/camera, input editing and keyboard dismissal, API consent and failure, Health replacement after editing, saved-food replacement, widget Log routing and in-place upgrade. Do not put synthetic meals into personal Apple Health.

No native compilation, SwiftUI rendering, real Keychain/HealthKit/WidgetKit/cryptography execution, launch-time improvement, live model accuracy, or real-device upgrade is claimed. Setup is in `setup.md`; update and flow details are in `UI-1.10.md`.
