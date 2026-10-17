# Verification — Recomp 1.6 DEXA / Apple Health

**Unsigned Xcode source project. No Apple SDK build, simulator launch or real iPhone testing was performed.**

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0. September 18, 2026.

## Checks actually run

| Check | Result | Scope |
|---|---|---|
| Portable Swift core, Debug | **242 passed, 0 failures** | 210 prior tests plus 32 new DXA Health tests; migration assertions updated to schema 5 |
| Portable Swift core, Release | **242 passed, 0 failures** | Same suite, optimized build |
| Production DiaryStore + labelled mock Health adapter | **119 checks passed** | 61 prior checks plus 58 new permission/selection/lifecycle checks |
| Server unit and HTTP tests | **42 passed, 0 failures** | Mocked AI provider, no live API request |
| Static interface checks | **77 passed** | Source membership, design tokens, project/plist/scheme consistency |
| Static DXA Health checks | **25 passed** | Mapping/routing/privacy assertions in source, not native API type checking |
| Swift syntax across all 36 app sources | Passed | Parser only; no SwiftUI/HealthKit SDK validation |
| Retained domains against supplied v1.5 archive | Byte-identical | Maintenance/scale engines, report reader/parser, food estimation and server; see log |

Logs: `core-tests.log`, `release-core-tests.log`, `store-checks.log`, `server-tests.log`, `interface-checks.log`, `dxa-health-static.log`, `source-checks.log`, `unchanged-domains.log`.

New core cases cover explicit whole-body region mapping, percentage fractions, kg/lb/g, lean soft tissue versus fat-free mass, missing/ambiguous/conflicting fields, snapshot non-mutation, timezone/DST/date validation, stable IDs separate from scale IDs, per-type receipts, attempts without success receipts, pending cleanup, no auto-opt-in, schema-4 migration and state round trips, and exclusion of own exported scans from scale points.

New coordinator cases exercise separate connection flags; explicit per-scan review; no unapproved backfill; partial write permissions; repeat-sync idempotence through receipts; corrected values; removal/restoration of fields; Health-only removal; durable failure/retry/restart; approval staleness; global/feature pause; and editing, deleting or pausing while a save is in flight. Attempt markers are inspected in the real temporary diary before the mock save returns. These tests use **the actual DiaryStore** but a mock instead of HealthKit.

Historical logs in `Historical-v1.5` are prior-version evidence, not current test runs. PDF fixtures were not rerendered or reinterpreted for this update; PDF ingestion code is unchanged.

## Not verified

- Native iOS compilation/linking (SwiftUI, HealthKit, PDFKit, Charts), signing, install or launch.
- Real Health permissions, save replacement versions, percent display, deletion predicates, cloud sync or source-metadata persistence.
- iPhone appearance, accessibility, new review-sheet navigation, timezone picker and date controls.
- Physical-device in-place upgrade and app-termination/locked-device failure behaviour.
- Full provider-report interoperability or clinical validity of scan interpretation/maintenance models.
- Live AI provider, camera, App Store/TestFlight distribution or macOS GitHub Actions.

Unit tests validate programmed rules on synthetic inputs. They are not medical validation or proof of real-device integration.

## On-Mac / device acceptance

1. Export existing data. Keep the same bundle ID/team; install over the old app rather than uninstalling. Run `./scripts/check.sh` on a Mac with Xcode and also build Release. Resolve native errors before use.
2. Use a throwaway test environment, not personal Apple Health, for synthetic readings. Verify v1.5 scans/diary/tags/queues survive upgrading to schema 5. Confirm old scans are unshared by default.
3. Add/review a scan while all Health permissions are granted. Without per-scan sharing approval, it must create no Health samples. Connecting DEXA alone must not backfill unapproved scans.
4. In the sharing review, grant only body-fat write permission. Verify 19.5% appears as 19.5%, not 0.195% or 1,950%; denied selected fields remain pending. Grant weight/lean later and retry.
5. Check whole-body kg/lb/g conversion. For explicit 65 kg lean soft tissue + 3 kg bone mineral, reviewed Health lean body mass must be 68 kg. Soft tissue alone, regional rows and undefined lean must not produce lean Health samples.
6. Confirm the source is Recomp, time matches the reviewed date/timezone, and repeated sync produces one current sample per chosen type. Check the metadata and approximate-time flag where inspection is available; do not assume Apple's UI shows custom metadata.
7. Edit weight and scan date, deselect one field, remove a field, restore it, and remove all exports. Verify corresponding exact Recomp samples are replaced/deleted while the original report and other apps' samples remain untouched.
8. Delete a shared scan while syncing is paused. Restart/reconnect and verify pending cleanup runs only when allowed. Test denied permissions and real transient save/delete errors; do not accept false completion.
9. Refresh normal Body/Trends views with scan exports in Health. Own DXA exports must not appear as bathroom-scale points, affect maintenance, or take Home/Girlfriend's tags. Check after local scan removal and in an isolated reinstall using the same bundle ID.
10. Delete a sample inside Health: the report must remain. Save sharing choices again to republish it. A copy from a provider's app must not be silently deleted or claimed to be deduplicated.
11. Review/confirm values, then change the scan through another flow: a stale sharing snapshot must be rejected. Try travel timezones and DST, plus denied permissions, cancellation and native sheet/alert presentation.
12. Confirm regional results, PDF bytes, clinic/scanner names, notes and source excerpts do not appear in Health metadata or estimator requests. Existing food/scales integrations still work independently.
