# Recomp 1.9.1 — verification and launch-work report

Source input: `Recomp-Direct-AI-v1.9.zip`. Execution: Linux x86_64, Swift 6.2.1, Node.js 22.16.0, September 18, 2026. No Xcode SDK, iPhone, Apple Health store, live OpenAI key or native simulator was used here. The user supplied warnings from their Mac; the changes have not been rebuilt on that Mac by this environment.

## Fixes and evidence

1. Explicitly discard the return value from the crypto key-buffer cleanup. The cryptography algorithm, parameters, format and secret storage are unchanged. Native CryptoKit/CommonCrypto execution was not rerun here.
2. Set `LSSupportsOpeningDocumentsInPlace = false` in the app plist and generator. This declares the existing import/copy policy; it does not add a document browser or direct Files-open handler.
3. Explicitly disable **copy-phase stripping in Debug**, retaining signing and the debug/previews dylib layout. We do not claim to have reproduced or eliminated every signed-binary-copy notice in the user's Xcode version. Those warning lines do not themselves establish a failed build.
4. Remove the second full JSON dictionary parse from `StateFile.load`. Schema version and state share a decoder. Old-format migration and invalid-file preservation are regression tested; current diaries are not rewritten on load.
5. Precompute diary-date query keys/intervals once per query, rather than per food or Health sample. Tests compare the bulk query with the prior per-record semantics across nine timezones and three calendar systems; Health duplicate IDs remain deduplicated. The widget and diary use the same faster selection path.
6. Share one maintenance report between the screen's summary and recommendation. No persistent calculation cache or changed energy-balance formula is introduced. Applying a proposed target still recomputes against current data.
7. Coalesce overlapping startup/foreground refreshes. A deterministic callback interleaving produced an extra Health read in the original coordinator and only one in the patch. Actual food saves during a sync still drain and persist all nutrient receipts.
8. Avoid rewriting/reloading unchanged widget content on minute ticks and receipt-only updates. The comparison does not suppress changes of date/timezone, clock rollback, privacy setting, visible values or entry count. A missing file causes a new write. Successful writes alone update the publisher's in-memory checkpoint. Actual WidgetKit behavior remains unverified.

These are limited optimizations, not proof of the cause of the reported simulator delay. An empty-diary core load was already extremely short in this environment. JSON storage still loads synchronously and retained photos/reports remain in the diary file; huge-diary and real-device performance are not certified.

## Tests executed

| Suite | Result / scope |
|---|---|
| Core Debug | **374 tests passed**, 365 retained + 9 new methods |
| Core Release | **374 tests passed**, optimized Linux core, not an iOS build |
| Original DiaryStore coordinator harness | **134 checks passed**, actual coordinator with mock Health/observation |
| Meal-estimator model | **17 checks passed**, mocked network/observation |
| Retained audit harnesses | **20 and 17 checks passed** |
| Travel coordinator / migration replay | **36 checks and 7 process executions passed**, no native timezone notifications |
| Production HTTP client / localhost | **24 proxy-route and 25 direct-route checks passed**, fake provider, no paid request |
| Optional server | **65 tests passed**, mocked provider |
| New startup coordinator | **8 checks passed**; original coordinator failed 2 assertions for the same duplicate-refresh issue |
| Static interface / feature / DXA wiring | **96 / 99 / 25 checks passed**, not UI tests |
| In-place updater | **13 checks passed** on isolated project copies with custom signing identifiers |
| Changed native Swift / configuration | Swift syntax parsed; plists, selected build settings and diff whitespace checked |

`full-gate.log` ends with `EXIT: 0` after the retained gate and the new startup coordinator. `coordinator-before.log` documents the reproduced original failure. `core-focused.log` records an early focused run of the nine added tests; all nine are also in both final core suites. The test source was subsequently consolidated into the existing `SecondAuditTests.swift` file so the in-place patch requires no Xcode target-membership changes.

Repeated Debug/Release execution is not counted as additional unique tests. There was **no new AddressSanitizer run** for this patch; historical sanitizer reports in other directories apply to those earlier sources.

## Measured core-path timings

Identical synthetic inputs, optimized standalone executables, same Linux toolchain. Reported numbers are medians; these are **not native launch times**. Attachments are framed byte fixtures for persistence, not decoded photos.

| Code path | Original v1.9 | Patched v1.9.1 | Runs each |
|---|---:|---:|---:|
| Empty diary / absent file | 0.001 ms | 0.001 ms | 9 |
| Load 2,190 food entries | 66.216 ms | 38.274 ms | 7 |
| Calculate one day's total from 2,190 entries | 5.852 ms | 0.023 ms | 21 |
| Load those entries plus 24 MiB attachments (about 34.7 MB JSON) | 182.289 ms | 114.870 ms | 5 |

Before/after checksums match. CPU load, Foundation implementation, device hardware and data shape affect these numbers. No claim that the whole app launches by these percentages faster is justified. See `benchmark-before.log`, `benchmark-after.log`, and `TestSupport/StartupHarness/Benchmark.swift`.

## In-place patch safety

The updater checks all selected source hashes and all payload hashes before writing. It refuses unexpected Swift/source edits. It preserves the bundle-ID, signing-team, App-Group, entitlement-path and signing-style values, leaves schemes in place, and adds only the Debug copy setting/version and explicit plist import policy. Existing sources are backed up before changes; per-file replacements are atomic and ordinary execution failures trigger rollback of completed replacements. A crash or full disk during rollback can still require restoring the source backup; this is not a filesystem transaction.

Tests cover dry-run non-mutation, patched source hashes, preserved signing/group metadata and custom plist keys, byte-identical schemes, original-source backup, repeated no-op application, changed-source refusal, corrupt-payload refusal and inner-directory path guidance. They execute in a temporary directory; no user's project, diary or account is accessed. Source rollback is not diary backup.

## New native timing test — NOT executed here

The existing UI-test file now includes `testLaunchPerformance`, using Apple's `XCTApplicationLaunchMetric(waitUntilResponsive: true)` over five launches. It retains the existing Debug-simulator-only isolated test diary and no Health/API connection. Its results are not prefilled and no platform-independent timing threshold is invented.

On the Mac, run `./scripts/check-native.sh`, or run `RecompUITests.testLaunchPerformance` in Xcode's Test navigator. Use Instruments' App Launch template to identify where the actual launch spends time. A physical-device optimized build is needed before claiming device performance.

## Still unverified here

Native build and warning output; SwiftUI rendering and maintenance-view update timing; native cryptography; UIKit/WidgetKit/HealthKit execution; application/extension signing; simulator and phone time-to-first-frame; actual slow-animation settings; large encrypted backups; in-place device upgrades and all previously documented real-provider/model limitations. Prior verification files remain historical, not current native evidence.

Version **1.9.1 / build 13 / diary schema 7**. No new permissions, API setup, server changes or database migration. Setup remains in `setup.md`; patch and warning details are in `STARTUP-1.9.1.md`.
