# Recomp 1.10.1 — bug-fix and design verification

Source input: `Recomp-Unified-Food-v1.10.zip`, SHA-256 `3822d7d2287628a791dce86b83411e62620aed82349cecd6b8e489ce4246bd86`.

Version **1.10.1 / build 15 / diary schema 7**. Tests executed on Linux x86_64, Swift 6.2.1 and Node.js 22.16.0, September 18, 2026 (Los Angeles). No Xcode, Apple SDK, simulator, iPhone, live API key or personal Health store was used.

**This is a tested source update, not a verified native iPhone build.** Portable/model tests do not establish SwiftUI rendering, native Health semantics, encrypted-backup execution or real-world nutrition accuracy. The user's earlier Mac build does not verify this update.

## Bugs reproduced before fixing

The original v1.10 core suite passed 384 tests. A new 12-check harness executing the original food model then failed **9 assertions**. This is not a count of nine distinct bugs.

| Finding | Change |
|---|---|
| Undo restored the food numbers but retained the replacement's estimated/verified status and food context. Undoing an AI result also retained the AI-used state. | Store a full food-edit checkpoint: values, name, context, draft, locks, verification override and AI-used state. |
| Undo could not recover large valid manual totals with no AI-compatible draft. | Preserve the independent nutrition total in every checkpoint. Do not require an AI draft to restore manual data. |
| Undoing a lock change stripped correct source-photo numbers and left an otherwise unchanged saved meal marked modified. | Track the photo revision of each checkpoint; preserve references only when the photos really match. |
| Duplicate attachment identities could be submitted to AI even though they were not saveable. | Use the same count/validity/identity checks for requests and saves. |
| An invalid timezone left Save enabled but could not produce a valid record. | Use an explicit save-validation reason and validate the entry clock at the save boundary. |
| Overlong typed context was silently truncated into a different AI draft. | Refuse that conversion and explain the limit; valid local nutrition outside the AI schema remains supported. |

`regressions-before.log` and `regressions-after.log` show the original focused assertions before/after. The expanded final harness has **41 checks**. Source-inspected design/flow issues below were tested after implementing their changes; not every one has a separate old-version failing runtime fixture.

## Additional fixes and design changes

- Numeric inputs receive a revision signal after canonical replacements, even when the new totals equal the old totals. This repairs invalid field text after choosing a usual or Undo. Undo restores the last valid numbers, not invalid raw text.
- Half/Double scales and retains individual ingredients instead of collapsing the meal into one aggregate. Known arithmetic preserves the prior estimated/verified status, protects the new portions and can be undone in one step.
- Unknown ingredient IDs cannot corrupt the lock set/history. Opening an existing ingredient preserves its lock; manual modifications default to protection. Ingredient sheets ask before discarding changes.
- Undo remains a toolbar action after the last ingredient is removed. Up to 20 nutrition checkpoints are retained. Photos, dates, notes and log options are outside nutrition Undo.
- Changing attachments clears obsolete numbered sources immediately. A response for superseded photos cannot overwrite the current draft. The suspended-response regression executes the production model with a controllable fake provider.
- Photo imports prepare a batch before appending it. A small ticket state machine prevents stale completion or cancellation from affecting a newer batch. Core tests exercise that state machine, not Apple's photo picker or JPEG decoding.
- No-op existing-meal Save closes without calling the diary update path. The view route has static/native-test coverage supplied; it has not been exercised on iPhone here.
- Thumbnail decoding is retained across unrelated form updates. CSV strings are built only for the requested export. These remove unnecessary work but are **not measured native performance improvements**.
- Analysis CSV stays available when target revisions or maintenance history exist without current day confirmations; core regressions cover its eligibility.
- The existing concentric rings now sit beside the readouts when they fit, with a stacked fallback for narrow/large-text layouts. Exact values, approximation markers, small nonzero balances, color-independent labels and Reduce Motion support remain.
- Food rows omit repetitive successful-save/export status but retain pending writes. Photos use a compact editable strip. Settings is grouped, with Apple Health and Your usuals submenus. Supplementary logging options and UTC details are expandable; important consent/timezone/data-loss warnings remain.

## Tests actually run

| Check | Result | Scope |
|---|---:|---|
| Unmodified input core baseline | **384 passed** | Baseline, not a bug-free guarantee. |
| Updated core, Debug | **391 passed** | 384 retained + 7 new methods. |
| Updated core, Release | **391 passed** | Optimized Linux core, not iOS Release. |
| Core AddressSanitizer | **391 passed** | Leak detection explicitly disabled. |
| New food-edit harness | **41 passed** | Production model/store, real temporary files, fake Health/observation/AI. |
| Same food-edit harness with AddressSanitizer | **41 passed** | Leak detection disabled; no detected address errors in these cases. |
| Retained unified-food harness | **43 passed** | Actual model/store; fake Health/AI. |
| Retained diary coordinator | **134 passed** | Fake platform adapter. |
| Retained estimator harness | **17 passed** | Fake network/observation. |
| Startup coordinator | **8 passed** | Existing refresh/persistence regressions. |
| Earlier audit harnesses | **20 / 17 passed** | Existing race, pause and edit checks. |
| Travel coordinator and migration replay | **36 checks + 7 process executions passed** | Linux timezones/filesystem, fake Health. |
| Proxy/direct HTTP client harnesses | **24 / 25 passed** | Real localhost transport with synthetic provider data, no paid API. |
| Optional Node server | **65 passed** | Fake upstream provider. |
| Source-patch installer | **30 passed** | Isolated source copies; no account, phone or diary. |
| Existing/new food-UI source contracts | **39 / 21 passed** | Static wiring/contrast, not rendered UI tests. |
| Other static interface/feature/DEXA checks | **96 / 99 / 25 passed** | Source and project assertions. |
| App/widget/native-test Swift syntax | **58 files parsed** | Not Apple SDK type-checking. |
| Configuration and tooling | **Passed** | Plists, entitlements, scheme XML, project, assets and script syntax. |
| Native gate attempt | **Unavailable, exit 2** | Explicit Xcode requirement, not a pass. |

Repeated configurations are not added together as additional unique tests. The seven new core methods include **1,000 deterministic photo-ticket sequences** within one method, not 1,000 extra XCTest cases. All existing seeded core scenarios remain. Sanitizer commands set `ASAN_OPTIONS=detect_leaks=0`; these results are not a leak-freedom or security audit claim.

## Preserved code and patch safety

All **20 other Core files, 10 other Services files, and all 12 Server files are byte-identical to v1.10**. Core changes are limited to the export-eligibility predicate in `AdaptiveModels.swift` and `PhotoImportSession` in `MealAttachments.swift`. `MealEstimatorModel.swift` is the only changed service. Health adapters, scale/travel/maintenance formulas, backup cryptography, Keychain and HTTP/API contracts are not rewritten.

The patch checks every replacement's original and payload hash before any write. It preserves bundle IDs, signing team, App Group, entitlements and schemes; changes build/marketing versions in place. It rejects source/metadata/rollback-directory symlinks and refuses unexpected source changes. Existing files are backed up; writes are atomic per file, and a simulated mid-update error verifies rollback of completed writes. A disk failure/crash during rollback can still need manual recovery; this is not a filesystem transaction or a diary backup.

Two full-source upgrade chains also pass: v1.9 → supplied v1.10 patch → this patch, and v1.9.1 → supplied v1.10 patch → this patch, retaining a custom app identifier. Tests also cover dry-run nonmutation, all payload hashes, custom/binary plist values, modes, new-file tracking, repeated application, partially current sources, corrupted payloads and malformed projects. Keep your original DEXA reports and a verified diary backup separately.

## Evidence

The **full source ZIP** contains raw logs under `Verification/Polish-1.10.1/`. The smaller in-place patch includes this report and its own payload hashes (the archive-wide MANIFEST-SHA256.txt is for the default full ZIP, not a custom-signed project); use the full ZIP for the raw execution logs.

- `baseline-core.log` / `.exit`: original 384-test baseline.
- `regressions-before.log`, `regressions-after.log`: initial 12-check before/after assertions.
- `polish-expanded.log` / `.exit`: all 41 expanded food-edit checks.
- `core-model-gate.log` / `.exit`: all core/model/travel suites passed; this full invocation then stopped on an obsolete static check for the literal text ‘Photo role’.
- `final-checks.log`: after updating that assertion to check the editable role picker in the new photo-details screen, all static checks and the remaining proxy/direct network and 65 server tests completed successfully. This continuation used `set -e`; no separate shell-exit file was captured. Application source did not change between the two stages.
- `asan.log`, `composer-asan.log` / `.exit`: instrumented core and actual model harness.
- `patch-tests.log` / `.exit`: isolated updater checks.
- `source-checks.log`: Swift parser, configuration and byte comparisons.
- `native-attempt.log` / `.exit`: unavailable-Xcode failure, exit 2.

Earlier `composer`/`estimator` development runs were interrupted by a source edit during compilation and are not passing evidence. `intermediate-gate.log` stopped on a missing argument in a newly added synthetic test fixture; it was fixed before the final two-stage verification. Neither is presented as a product bug or final successful run. No single all-green invocation of check.sh is claimed: the complete set of its checks passed across those two stages, on unchanged final application code. All other versioned verification directories are historical.

## On your Mac and iPhone — still required

Apply the patch with Xcode closed, reopen the same project and run:

```bash
./scripts/check-native.sh
```

The runner creates its own disposable simulator, runs native core/crypto/UI tests and builds the app/widget in Release. **It has not run successfully here.** Three new native UI cases cover food-edit Undo, portion-field updates and opening Health settings without connecting. Existing tests retain navigation, save/relaunch, cancellation, Check isolation, usuals and launch measurements.

After a successful build, verify small screens, large text, dark/increased-contrast appearance, VoiceOver, Reduce Motion, photo/camera selection and cancellation, sheets and keyboard focus, privacy prompts, no-op save, Health update/deletion semantics and backups on the device. Test synthetic records only in the disposable simulator, never in personal Apple Health.

No native layout, launch-time improvement, real model accuracy, actual Keychain/HealthKit/WidgetKit/CryptoKit execution, App Review approval or clinical validation is claimed.

## API references

Apple's ViewThatFits and SwiftUI sheet/confirmation-dialog APIs informed the native layout and presentation choices; they do not establish that this app has passed Apple's compiler or runtime:

- https://developer.apple.com/documentation/swiftui/viewthatfits
- https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:)
