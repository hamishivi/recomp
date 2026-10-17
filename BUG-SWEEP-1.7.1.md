# Recomp 1.7.1 — bug sweep and regression report

Audited September 18, 2026. Input: `Recomp-Backup-Photos-Activity-Widgets-v1.7.zip`, SHA-256 `d94087591ff271abf8feb572411af022c84c839b0330d1482c8c5cde07a1774a`.

**This is a tested source patch, not a verified iPhone build.** Actual execution here used Linux x86_64, Swift 6.2.1, and Node.js 22.16.0. No Apple SDK, Xcode, simulator, iPhone, live AI provider, Strava account or personal Health store was available to this execution environment. Platform integration tests below are explicitly distinguished from portable tests.

## Important fixes

| Area | Reproduced problem | Fix and regression evidence |
|---|---|---|
| Health sync | A meal saved during the final asynchronous Health refresh could remain pending after that sync completed. | The final read is inside the queue-draining loop. An explicit suspended-read/save/resume regression now completes all four nutrient receipts. |
| Diary dates | A previous day's Health response could finish just after selecting another day and mark the wrong day refreshed. | Date selection immediately invalidates outstanding responses; completed reads also check their requested day. The old-day response cannot certify the new day complete. |
| Concurrent edits | An already captured food/measurement list could initiate additional writes using an older revision after an edit. | Compare each pending operation against the current revision before starting it; skip stale operations and drain the new revision. An operation already accepted by Health cannot be recalled. |
| Edited meals with photos | Correcting aggregate nutrition cleared the old AI breakdown. Reopening retained photos then started from an empty estimate rather than the corrected totals. | Normal-range saved totals seed a locked aggregate item, instead of inventing ingredients. Merely opening it does not count as an edit. |
| Photo evidence | A locked food's old “photo 1” could be attached to a different replacement photo after refinement. | Clear old photo numbers before refining a changed photo set, while retaining the original text/values and undo history. The server also rejects output referencing a photo that was not supplied. |
| Refinement limits | A photo-only correction near the context limit passed the button's validation, then failed because the generated clarification pushed it over the limit. | Preflight counts the actual generated clarification. A boundary regression verifies that it is disabled before requesting AI. |
| Future food | The coordinator accepted future food records, despite a separate no-logging checking mode. | Reject future food at the save boundary, before persistence or Health work. |
| Maintenance history | Correcting food invalidated the complete-day record, but could leave today's stale maintenance snapshot in the audit history when Health was off. | Re-evaluate/remove today's snapshot after successful food edits and deletions, independently of Health sync. Old historical snapshots remain historical records. |
| Failed pause | If a real disk write failed while pausing Health, the display cleared even though the persisted connection was still enabled. | Only clear caches and invalidate reads after the pause is successfully committed. Tested with an actual unwriteable destination, not a fake save-result Boolean. |
| Diary/backup validation | Nonfinite food dates, overflowing revision counters, impossible export receipts, duplicate saved-food IDs and invalid calendar dates could pass validation. | Reject inconsistent state before a diary save or backup restore. Valid schema-6 diaries remain supported. An invalid attempted save leaves the existing file byte-for-byte unchanged. |
| Server input | `application/jsonp` and similar prefix matches were accepted as JSON; an upstream API key could be configured as the phone's proxy password. | Require the JSON media type and independent server access credentials. The tests fail before the fixes and pass afterward. |
| Server response size | The upstream response was fully buffered before its size limit was checked. | Read a bounded stream and cancel once the limit is exceeded; a generated oversized stream now stops after a few chunks rather than being fully read. |
| Widget freshness | A cached widget view checked freshness against the timeline entry's old time, rather than the time it was being rendered. | Recheck against the wall clock on render, in addition to the existing midnight entry and timezone guards. Native refresh timing remains controlled by iOS and unverified here. |

The client still buffers its server response using URLSession before validating its size. The included proxy now strictly limits its upstream response, but the client is not a general untrusted-server sandbox: configure only a server you control. This is not a security audit.

## Tests actually executed

| Suite | Result | What it establishes |
|---|---:|---|
| Original unmodified core | 286 passed | Baseline; does not imply absence of bugs. |
| Original unmodified Node suite | 49 passed | Baseline with fake AI provider. |
| Updated Swift core, Debug | **297 passed** | Production portable models, arithmetic, persistence rules, migration, backup payload/restore gates, scale-aware trends, DXA mapping, activity math, widget snapshot rules. |
| Updated Swift core, Release | **297 passed** | Same rules with optimized Linux build; not an iOS Release build. |
| AddressSanitizer | **297 passed** | Instrumented Swift core execution without detected address errors. `ASAN_OPTIONS=detect_leaks=0`; leak detection was explicitly disabled. Not a claim of leak freedom or a security audit. |
| Los Angeles timezone rerun | **297 passed** | Full suite with `TZ=America/Los_Angeles`. |
| Sydney timezone rerun | **297 passed** | Full suite with `TZ=Australia/Sydney`. |
| Existing production coordinator harness | **134 checks passed** | Actual DiaryStore control flow with a labelled fake Health adapter. |
| Existing estimator-model harness | **17 checks passed** | Actual estimator model with fake network/observation. |
| New combined audit harness | **20 checks passed** | Deterministic interleavings, incorrect-day responses, photo locks, real disk failures/restart, and invalidated maintenance snapshots. |
| Updated Node unit/local HTTP suite | **61 passed** | Real localhost HTTP requests with fake AI responses, including concurrency, cancellation, truncated/chunked uploads, auth, quotas, size limits and sanitized errors. No paid API request. |
| Static interface / feature / DXA wiring | **90 / 93 / 25 passed** | Selected wiring and asset checks, not native UI behavior. |
| Swift parser | **52 source files parsed** | App, widget and new native-specific tests parse; not Apple-SDK type-checking. |
| Project/configuration | Passed | OpenStep project parsed by `plutil`; 209 unique project objects resolve; property lists, entitlements, scheme and script syntax checked. |
| Independent encrypted fixture | Passed | Python decrypts the supplied synthetic fixture and rejects a changed authentication tag. Does not execute Apple's cryptography implementation. |

The 11 added core test methods include **2,500 deterministic randomized scenarios**: 1,000 hypothetical-food calculations, 1,000 overlapping-sleep interval sets compared with an independent second-by-second reference, and 500 same-scale trend histories with random constant offsets spanning daylight saving. These are scenarios within the 297 tests, not 2,500 additional XCTest methods. Repeating the suite in different configurations is not counted as additional unique tests.

Node's coverage run reports **96.72% line / 87.69% branch coverage for `estimate.mjs`**, and **91.03% line / 93.42% branch coverage for `server.mjs`**. Coverage is an execution measure, not proof of correctness or vision-model accuracy.

### Before/after evidence

`Verification/Audit-1.7.1/` contains raw logs, including:

- `baseline-core.log`, `baseline-server.log` — passing original suites.
- `regressions-before.log` — nine failing assertions in the initial 11-check audit harness.
- `core-regressions-before.log` — nine failing assertions in the added core tests before validator fixes.
- `server-regressions-before.log` — four failing tests before server fixes.
- `disk-history-before.log` — two additional failed state-management assertions before those fixes.
- `regressions-after.log`, `core-tests.log`, `release-tests.log`, `store-checks.log`, `estimator-checks.log`, `server-tests.log`, `server-coverage.log`, `address-sanitizer.log`, `timezone-*.log` — passing updated runs.
- `native-attempt.log` — native gate explicitly fails with exit code 2 because Xcode is unavailable; it is not recorded as a passing native test.

A failed assertion count is not a unique bug count. Some tests contain several assertions for one issue.

## Native tests added, NOT executed here

The old Xcode scheme had no test bundles. It now includes:

- **RecompNativeTests:** all core test sources compiled against Apple's Foundation, plus four CryptoKit/CommonCrypto tests: independent fixture interoperability, exact round trips/randomness, wrong password/tampering, and Unicode/NUL password bytes. This target is hostless and does not access Health.
- **RecompUITests:** five simulator smoke tests for tab navigation, food save/relaunch, cancelling food, no-log checking, and local weight entry. UI tests use a separate Debug-simulator-only diary and do not publish synthetic widget totals. They never connect to Health or the AI service. Screenshot attachments are retained in the test result.

These new tests have been source-parsed and wired into the project, **not compiled, launched or passed**. They may expose additional native errors when first run. They do not replace real Health permission/replacement testing, camera/PDF checks, widget rendering, large-backup performance or testing an upgrade over actual device data.

Run on your Mac with full Xcode and an iOS 17+ Simulator runtime:

```bash
./scripts/check-native.sh
```

The runner creates a **new disposable simulator**, runs the exact native Mac backup harness, builds/tests the app and XCTest targets in Debug, then builds the app and embedded widget in Release. It saves `.xcresult` results/screenshots/logs under `.native-results/` and deletes only its own simulator on exit. It refuses to run without Xcode. It does not install on your iPhone or erase an existing simulator.

For the entire gate:

```bash
./scripts/check.sh --require-native
```

The updated macOS GitHub Actions workflow runs that gate and uploads native results. The workflow has been supplied, not run in a remote repository. The default portable `./scripts/check.sh` remains usable on Linux and prints the native limitation; `--require-native` fails instead of treating that limitation as a successful native test.

## Update safely

Version **1.7.1**, build **9**, retains diary schema **6** and the v1.7 feature set. Keep the **same bundle identifier, App Group and signing team**, and install over the existing app; do not uninstall. Retain original scan reports and a verified backup first. Update the optional `Server/` folder as well to get the response validation and streaming limit fixes. No API key, live account data or real personal measurements are included.

A malformed diary is refused without overwriting it; the patch does not silently rewrite invalid records or repair inconsistent backups. Real-device migration, HealthKit sync/permissions, widget behavior, native encrypted backup restore, camera estimation and clinical/model accuracy remain unverified.

## Platform references

- Apple UI testing: https://developer.apple.com/documentation/XCUIAutomation
- Apple command-line test automation: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/08-automation.html
- Apple required-reason APIs: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype

The app/widget privacy manifests now declare their file-metadata access reasons in addition to the existing UserDefaults reason. This is a source-level declaration, not App Review approval or a complete privacy audit.
