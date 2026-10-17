# Recomp 1.7.2 — second bug pass

Audited September 18, 2026. Input: `Recomp-Bugfix-v1.7.1.zip`, SHA-256
`d557ce6d31d1775d11bf2fcef0e27e0c71440e7f784bade3fc73532503f94275`.

**Tested source update, not a verified iPhone build.** Execution used Linux x86_64,
Swift 6.2.1 and Node.js 22.16.0. The actual HTTP client now has executable localhost
coverage; Apple Health, Keychain, CryptoKit, WidgetKit, UIKit and SwiftUI still have
no native runtime verification here. No live AI, Strava, Strong or personal Health
account was contacted.

## Fixes

| Area | Finding | Change and evidence |
|---|---|---|
| Actual iPhone-client networking source | v1.7.1 buffered an entire HTTP response before enforcing 250,000 bytes. Both declared-length and chunked 5 MB fixtures were downloaded in full. | Replace `URLSession.data(for:)` buffering with one bounded, delegate-driven transfer. Reject oversized declared bodies at headers and enforce the cap before each append. Decompressed/chunked responses are bounded too. Real localhost regressions failed before and pass after. |
| Response validation | The client accepted valid JSON labelled `text/html`, and meal evidence referencing photo 1 when no photo was supplied. | Require the JSON media type and check photo references against the actual request, in addition to existing model validation. Both before/after cases execute the production service code, not a mock service. |
| Overall network deadline | An intermediate transport revision relying only on Foundation timeout settings did not end a continuously trickling localhost response within its configured test deadline. | Add an independent monotonic dispatch deadline (100 seconds by default), plus existing idle/resource configuration. The shortened test now terminates with `URLError.timedOut`; receiving another byte cannot extend that timer. This was observed on Linux FoundationNetworking, not on an iPhone. |
| Health pause and current analysis | Removing imported weights by pausing Health left today's previously calculated maintenance snapshot in the audit history. The general Health pause also left activity reads enabled. | Re-evaluate/remove today's snapshot after clearing imported data, and commit activity-off alongside food/body/DEXA-off. Settings exposes **Pause all Health connections** whenever any connection is enabled. Historical snapshots remain an audit trail; existing Health samples and system permissions are not deleted/revoked. |
| Activity connection | The UI proceeded to read activity after a successful permission prompt even if persisting the local opt-in failed. Overlapping foreground/preference refreshes could also request the same history twice. | Persist the enabled preference successfully before reading. A production-controller regression uses an actual unwritable file destination and confirms zero adapter reads. Coalesce concurrent enabled refreshes; a pause still invalidates late results. Successful retry clears the previous connection error. |
| Verified meals | Simply reopening an unchanged verified meal in the breakdown editor changed its `isEstimate` flag to true. | Preserve the original verified status when nutrition is unchanged and no new AI response was used. Modified nutrition and new AI results stay estimated. Regression covers all three outcomes. This is bookkeeping, not independent nutritional verification. |
| Calendar settings | Stored diary keys followed the display calendar; Buddhist, Hebrew, Islamic and Japanese calendars produced different years. Gregorian edit-invalidation could miss the matching completed day. | Persist/decode Gregorian civil-date keys using the original local timezone, regardless of display calendar. Three new regressions include invalidating completion after an edit and preserving the intended date. |
| Step-summary crash | Extreme finite step counts and an overflowing percentage change could trap during `Double` → `Int` conversion. | Validate representable inputs and derived values; skip invalid comparisons and format activity values without unsafe integer conversion. One pre-fix test actually terminated with signal 4. Added cases cover the overflow, tiny denominator, invalid inputs and ordinary 8,000-versus-4,000 step data. These are numeric representation checks, not physiological limits. |
| Proxy error cleanup | Non-2xx upstream AI responses were thrown away without cancelling their unread response stream. | Cancel the stream before raising the existing sanitized error. Four regressions cover 401, 403, 429 and 500; all failed before and pass after. |

The bounded client uses an ephemeral session with no cache/cookies/credential storage,
rejects redirects, and uses exactly-once completion guarded by a lock. Cancellation
closes the request. It does not introduce retries or change the server URL/token setup.
The HTTPS requirement on a real phone is retained. This is not a security audit,
a guarantee of zero memory copies, or a live vision-accuracy test.

## Tests executed

| Suite | Result | Scope |
|---|---:|---|
| Unmodified v1.7.1 core baseline | 297 passed | Established baseline before the new regressions. |
| Updated Swift core, Debug | **303 passed** | 297 retained + 6 new XCTest methods. |
| Updated Swift core, Release | **303 passed** | Optimized Linux core, not an iOS Release build. |
| Core with AddressSanitizer | **303 passed** | `ASAN_OPTIONS=detect_leaks=0`; leak detection explicitly disabled. |
| America/Los_Angeles and Australia/Sydney reruns | **303 passed in each** | Same tests, not additional unique methods. Four alternative display calendars also have explicit regressions. |
| Retained DiaryStore harness | **134 checks passed** | Production coordinator against labelled Health/observation test doubles. |
| Retained estimator harness | **17 checks passed** | Actual estimator model, fake network and observation. |
| Retained v1.7.1 combined audit | **20 checks passed** | Existing sync/date races, disk failures and meal-correction regressions. |
| New combined audit | **17 checks passed** | Maintenance pause, verified meals, persistence-before-activity, refresh coalescing, late results and global pause. |
| Actual HTTP client + localhost server | **24 checks passed** | Production HTTP service/transport; only Keychain configuration replaced with a synthetic loopback endpoint/token. No paid AI provider. |
| Same HTTP suite with AddressSanitizer | **24 checks passed** | Includes bounded/decompressed data, deadline and cancellation; leak detection disabled. |
| Node unit/local HTTP suite | **65 tests passed** | 61 retained + 4 upstream cleanup regressions; provider is mocked. |
| Static interface / feature / DEXA checks | **91 / 94 / 25 passed** | Source/asset/project wiring only. |
| Swift source parsing | **53 files parsed** | App, widget and native-specific tests; not Apple-SDK type-checking. |
| Syntax / project checks | Passed | Python/shell/Node, plist/entitlements/privacy manifests, scheme XML, OpenStep project and diff whitespace. |
| Native gate attempt | **Blocked, exit 2** | Xcode and iOS Simulator unavailable; not counted as a pass. |

The network suite checks declared/chunked limits, exactly-250,000-byte JSON,
gzip decompression, wrong content type, malformed JSON, invalid evidence,
error status, redirect refusal, in-flight and pre-request cancellation, recovery
and a trickling-response deadline. A burst contains **100 requests**, with half
cancelled: all requests finish and all 50 uncancelled ones return valid data.
These are scenarios inside the 24 checks, not 100 additional XCTest methods.
The script has a separate 60-second watchdog so a regression cannot hang the gate
indefinitely. Existing 2,500 seeded core scenarios from v1.7.1 remain in the suite.

The full portable gate was rerun on the final source. Repeated configurations and
sanitizer runs are deliberately not added together as a count of unique tests.
Passing tests establish the tested cases, not that every possible bug is fixed.

## Before/after evidence

Raw logs are in `Verification/Audit-1.7.2/`:

- `baseline-core.log`: unmodified 297-test baseline.
- `core-before.log`: calendar regressions, six failed assertions across three methods.
- `coordinator-before.log`: two failing assertions in the initial four-check harness.
- `network-before.log`: four failing checks in the original 16-check network harness.
- `server-before.log`: four failed upstream cleanup tests.
- `extreme-step-before.log`: actual conversion trap / unexpected signal 4; core dump disabled.
- `network-expanded.log`: failed elapsed-time check on the intermediate transport; the streaming fixture was manually terminated to end that failing run. The final transport uses the independent timer and the harness now has its own watchdog.
- `pause-activity-before.log`: one failing assertion showing the general pause left activity enabled.
- `final-gate.log`: final Debug/Release, harness, network, Node and static results.
- `asan.log`, `network-asan.log`, `timezone-*.log`, `source-checks.log`: additional completed checks.
- `native-attempt.log`: the explicit unavailable-Xcode failure.

A failed-assertion count is not a count of unique bugs. Some new activity-flow
checks were introduced alongside refactoring rather than executed against the
old UI. The old UI defect was found by source inspection; the new flow's tests
execute actual controller code against a fake Health reader and real filesystem
failures. No native permission dialog was exercised.

## Run the tests

```bash
# Full portable gate; reports the native limitation on Linux:
./scripts/check.sh

# Focused new regressions:
swift test --filter SecondAuditTests
./scripts/check-audit2.sh
./scripts/check-network.sh
(cd Server && node --test)

# Optional Linux/macOS address instrumentation of the client harness:
ASAN_OPTIONS=detect_leaks=0 RECOMP_NETWORK_ASAN=1 ./scripts/check-network.sh

# On your Mac with full Xcode and an iOS 17+ simulator runtime:
./scripts/check.sh --require-native
# Or the native gate alone:
./scripts/check-native.sh
```

The existing native gate creates its own disposable simulator, exercises the exact
native backup implementation, runs core/crypto/UI tests in Debug, and builds the
app plus widget in Release. It does not run against a paired iPhone or erase an
existing simulator. **That gate was not able to run here.**

## Remaining gaps

Native SwiftUI/UIKit/HealthKit/WidgetKit/CryptoKit/CommonCrypto/Keychain builds and
runtime, actual simulator UI and device updates, Health permissions and sample
replacement/deletion, camera/photos/PDF import, large encrypted-backup restore,
widget rendering/privacy, live Strava/Strong records and live AI estimation remain
unverified. The networking harness executes Linux FoundationNetworking, not Apple's
Foundation implementation; real-device HTTPS, suspension and lifecycle still need
verification. No medical accuracy or clinical validation is claimed.

No restore/cryptography algorithm was changed in this pass. Existing payload,
restore-safety and identity-preservation tests were rerun, but they do not execute
native encryption or prove real Health semantics after a restore.

## Update safely

Version **1.7.2**, build **10**, diary schema **6**. No migration, new permission,
App Group or server configuration change is needed. Use the same app bundle ID,
App Group and signing team, and install over the current app. Do not uninstall.
Keep original reports and a verified backup separately. Deploy the updated
`Server/` folder to get the upstream error-stream cleanup fix as well.

Existing records are not silently rewritten. A completed food day saved under
an older non-Gregorian display calendar may already have a wrong stored year;
the patch does not guess how to repair historical dates. Recheck and reconfirm
those affected days. Correctly stored Gregorian dates and timezone boundaries
are preserved. The maintenance equation, target limits, DXA mapping and workout
summary fields are unchanged.

## API reference

Apple's URLSession delegate response-disposition contract:
https://developer.apple.com/documentation/foundation/urlsession(_:datatask:didreceive:completionhandler:)

This reference supports the API choice, not proof that this app passed a native build.
