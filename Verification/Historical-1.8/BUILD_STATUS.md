# Verification — Recomp 1.8 travel update

**Tested source project, not a verified native iPhone build.** Execution environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0. September 18, 2026. No Apple SDK, Xcode, iPhone simulator, actual HealthKit store, live Strava/Strong account or live AI request was used.

Input: `Recomp-Bugfix-v1.7.2.zip`, SHA-256 `453a99a9241f38e6c23dcb348635a5eff7e2cfe2df02e00abb9abfb2fe282064`.

## Executed on the final source

| Check | Result | Scope |
|---|---:|---|
| Full portable gate, `./scripts/check.sh` | **Exit 0** | Includes the suites below; explicitly reports native verification was not performed |
| Swift core, Debug | **339 passed, 0 failures** | 303 retained plus 36 travel-specific XCTest methods |
| Swift core, Release | **339 passed, 0 failures** | Optimized Linux execution, not an iOS Release build |
| Swift core, AddressSanitizer | **339 passed, 0 failures** | `ASAN_OPTIONS=detect_leaks=0`; leak detection disabled |
| Core reruns in LA, Sydney, Toronto and Paris | **339 passed in each** | Same methods under four process timezones, not additional unique tests |
| Retained DiaryStore coordinator harness | **134 passed** | Actual store, fake Health adapter |
| Retained meal-estimator harness | **17 passed** | Actual model, fake network/observation |
| Retained first / second audit harnesses | **20 / 17 passed** | Earlier control-flow/race regressions |
| New travel coordinator harness | **36 passed** | Actual store, temporary filesystem and mocked Health range reads/writes |
| Legacy-diary process replay | **7 successful executions** | Create in LA; reopen in Sydney, Adelaide, Vancouver, Toronto, Paris, London |
| Actual HTTP client / localhost server | **24 passed** | Production Linux FoundationNetworking client; no paid AI |
| Node unit / localhost tests | **65 passed** | AI provider mocked; server source unchanged |
| Static interface / feature / DEXA checks | **93 / 96 / 25 passed** | Wiring/assets, not native UI or Health tests |
| Swift source parser | **55 files passed** | Production app, widget and native-specific test sources; not Apple SDK type checking |
| Plists, schemes, assets, scripts, whitespace | Passed | Configuration/syntax checks |
| Native gate attempt | **Unavailable, exit 2** | Xcode/macOS required; not a passing native test |

All counts refer to actual executed checks. Repeated configurations are not added together as unique tests. The 36 travel core methods include **120 seeded synthetic itinerary scenarios** inside one method; those are not 120 extra XCTest methods. Earlier randomized scenarios remain in the retained suite. Passing these tests does not validate the maintenance model or guarantee all travel cases are correct.

## Travel cases covered

The core tests exercise frozen local diary membership in nine viewing zones and alternative display calendars; Seattle/Sydney skipped and repeated civil dates; timestamps and IDs preserved through zone correction; body chart date stability; valid source Health metadata versus explicitly unknown metadata; inferred legacy clocks and atomic schema-7 migration; JSON backup payload/restore identity preservation; half-open coverage boundaries; own-export and exact-ID deduplication; timestamped partial-boundary food totals; rejection of prorated partial legacy snapshots; duplicate/outside/mismatched events; differing-zone aliases; overlapping and excluded coverage; small gaps; unfinished/future confirmations; edit/move invalidation; maintenance and proposals independent of viewing timezone; 12/36-hour synthetic flight periods; actual-hour DST normalization in LA/Sydney/Paris; same-scale offset separation; sparse/disconnected scales; CSV timezone/coverage fields; and widget/diary agreement after a flight.

The coordinator harness checks automatic clock stamping and persistence, ordinary and 36-hour food review, explicit overlap replacement, stale preview rejection after a food change, invalidation after edits/moves, exact requested Health interval boundaries, failed/paused Health reads, invalid zone/time rejection, delayed body-sync clock preservation, selected historical date versus Today on a simulated live zone change, selectable future-looking civil labels after crossing the date line, and safe backfill defaults.

Those live timezone switches use Linux process `TZ` plus Foundation cache reset. They do **not** exercise an iPhone's actual system notifications or view lifecycle. The seven process replays establish that migration freezes its assumed display zone once on disk; they do not prove that an inferred old capture zone is historically correct.

## Regression evidence and logs

Current raw evidence is under `Verification/Travel-1.8/`:

- `baseline.log`: unmodified v1.7.2, 303 core tests passed.
- `final-gate.log` / `.exit`: final-source full portable gate; exit 0.
- `address-sanitizer.log` / `.exit`: all 339 core tests passed, leak detection off.
- `timezone-*.log`: four complete 339-method reruns.
- `coordinator-travel.log`: earlier standalone 36-check/replay pass; the final gate reruns it too.
- `widget-before.log`: newly added travel regression failed three assertions while WidgetBuilder still used the current timezone to regroup meals. This exposed an app/widget mismatch introduced by retaining the old builder alongside the new diary logic.
- `widget-after.log`: the same method passed after switching the widget to captured diary membership. The final Debug, Release and sanitizer suites also include it.
- `swift-parse.log`, `config-checks.log`: parser and configuration results.
- `native-attempt.log` / `.exit`: explicit unavailable-Xcode failure, exit 2.

Other `*-first`, `*-refined`, `core-debug` and `intermediate-gate` logs document development stages, not final release results. The intermediate full gate stopped because a source file was edited during its compilation. It is not counted as a passing run or a product bug; the final gate was rerun successfully on stable source. Historical directories from prior releases retain their original reports and limitations.

Changes to older tests are limited to intentional contract changes: schema 7, inferred optional clocks on legacy migration, acceptance of other viewing timezones, and elapsed-hour DST expectations. No original test method was removed. New tests separately verify the added clock fields and original IDs, values and receipts.

## Native and real-world gaps

Not verified: native SwiftUI/Charts/HealthKit/WidgetKit/UIKit compilation; actual iOS timezone and significant-time-change events; native date pickers and ambiguous clock-hour interaction; Xcode signing and App Groups; widget update/redaction timing; Health permission handling, source metadata, delayed-write/replacement/deletion semantics; native backup encryption and physical-device restore/upgrades; camera/PDF/AI workflow; Dynamic Type/VoiceOver/layout; App Review; clinical or real-world accuracy of the maintenance heuristic.

The export adapter's timezone assignment was inspected in source. The store harness sees the queued record's clock but cannot execute `HKQuantitySample` or prove how Apple Health displays metadata. Imported sources may omit or use inaccurate timestamps/timezones. Food coverage is explicitly reviewed, not inferred from an empty Health result.

## Reproduce

```bash
swift test
swift test -c release
./scripts/check-travel.sh
./scripts/check.sh
# Optional sanitizer execution, separate build products:
ASAN_OPTIONS=detect_leaks=0 swift test --scratch-path /tmp/recomp-travel-asan --sanitize=address
# macOS + full Xcode, required to establish native compilation:
./scripts/check.sh --require-native
```

The native gate creates its own disposable simulator and runs existing native core/crypto/UI targets plus Release app/widget build. It does not install on a paired iPhone or intentionally write synthetic records to personal Health. The new travel core tests are included in the generated native test target but have **not run there**.

Version 1.8 / build 11 / schema 7. See `TRAVEL-1.8.md` for update and flight-day instructions. `Server/` is byte-identical to the baseline; no server redeployment is required for this update.
