# Verification — Recomp 1.2 body + maintenance update

**Unsigned Xcode source project. This delivery was not compiled with Apple's SDK or run on an iPhone.**

## Actually run for this delivery

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0. September 18, 2026.

| Check | Result |
|---|---|
| Portable Swift package, Debug | **136 tests passed, 0 failures** (62 retained + 74 new) |
| Portable Swift package, Release | **136 tests passed, 0 failures** |
| Production DiaryStore with labelled mock adapter | **21 coordinator checks passed**; Swift type-check/control flow, not real Apple frameworks |
| Node unit + local HTTP tests | **42 tests passed, 0 failures**, mocked AI provider; no live API request |
| All app Swift files, parser only | Passed; **not** native Apple SDK type-checking |
| Generated Xcode membership | All current app Swift sources included |
| Plists, entitlement, scheme XML and project references | Parsed / consistency checked |
| Node, shell and Python script syntax | Passed |

Logs: `core-tests.log`, `release-core-tests.log`, `store-checks.log`, `server-tests.log`, `source-checks.log`.

New core coverage: kg/lb and cm/in conversion; percentage-point/Health fraction conversion;
body record validation; source-aware deduplication; daily local-priority medians; exclusions;
version receipts; tombstones; schema-1 migration, schema-2 round trips and future-schema
rejection; deterministic maintenance arithmetic; missing/partial/today/future/stale data;
required matching intake and weigh-in intervals; sparse and duplicated weigh-ins; DST and
time-zone handling; water spikes/outliers and trend disagreement; no body-fat dependency;
comparable multi-reading waist changes; cooldowns; opt-in guidance; realistic-input and
rapid-change suppression; bounded target adjustments; consistent macro budgets; food
confirmation invalidation; target audit history; CSV escaping; isolated read-only demo data.

The coordinator harness compiles the actual `DiaryStore.swift` against explicit portable
Combine/HealthKit test doubles and an isolated temporary diary path. Checks cover multi-metric
persistence, food edit/confirmation invalidation, independent body/nutrition enabling, denied
metrics remaining pending, versioned edit receipts, deletion queues, failure/retry, pause,
restart and rejection of an unsupported proposal. This does **not** prove Apple's runtime
permission, replacement, deletion or lifecycle semantics.

## Not verified here

- Native SwiftUI/Charts/UIKit/HealthKit/PhotosUI/AVFoundation/Security compilation or launch.
- Xcode signing, simulator UI, accessibility/layout, keyboard/sheet interactions and runtime performance.
- Physical iPhone upgrade/migration, denied or partial Health permissions, real Health read/write,
  sample replacement, tombstone deletion, percent/length units in Apple's UI or source filtering.
- Native photo/camera flow, live AI estimates, HTTPS service deployment or provider billing.
- Real-world accuracy of maintenance estimation, sensitivity ranges, body composition or recommendations.
- Mac GitHub Actions, device deployment, App Review or medical safety/clinical validation.

Unit tests verify programmed rules against synthetic cases. They do not validate the fitness
model or prove real-device integration works. Historical camera acceptance checks remain in
`PHOTO_ACCEPTANCE.md`; its previous-version results are historical, not new native verification.

## Device acceptance checklist for 1.2

1. Run `./scripts/check.sh` on a Mac with Xcode; resolve any native SDK/compiler issues. Run Debug and Release.
2. Update the existing app using the same bundle ID/team, without uninstalling. Export first.
   Confirm old meals, AI breakdowns, templates, targets and queues remain; no fake measurements appear.
3. With no server and no Health permissions, log/edit/delete weight, body fat and tape measurements.
   Check decimal comma, kg/lb and cm/in switches, timestamps, notes, blank optional fields and history.
4. Enter 19% body fat and 90 cm waist, grant only selected write permissions, sync and inspect Health.
   Verify 19%, not 0.19% or 1,900%, and 90 cm, not 90 m. Verify denied metrics remain pending.
5. Edit dates/values and verify each own Health sample is replaced, not added twice. Delete a local
   record, restart/retry and confirm cleanup without deleting anything created by another app.
6. Import a scale weight/body-fat reading, compare raw-source history, local daily priority,
   hidden/read-restored behaviour and trends. Empty reads must never be labelled proof of permission.
7. Turn measurement sync off while leaving nutrition on, and vice versa. Test pausing during an
   in-flight save; a request already accepted by Health may finish. No new writes should start afterward.
8. Confirm a fully logged food day, then edit/delete/move a local meal or refine its saved AI estimate.
   Both affected dates must require reconfirmation. Imported edits require reviewing snapshots again.
9. Check all six labelled example trends. Nothing is written to the diary, targets or Health.
10. With a controlled test diary, compare 21–42-day maintenance results against the formula and
    algorithm tests; missing days and today's incomplete interval must not silently enter totals.
11. Enable adult suggestions, review/apply an appropriate proposal, and verify before/after targets,
    macro totals, historical audit record and 14-day cooldown. Check data changes invalidate stale previews.
12. Test body-fat jumps, an isolated unusual weight, different waist methods and rapidly changing weights.
    Body fat must not affect the calorie model; uncertain/rapid trends should suppress target proposals.
13. Export all three CSVs and inspect units, consented Health-total snapshots and formula escaping.
    Restart the app; no photos or Health records should have been sent to the optional AI server.
14. Review actual deployed service privacy/settings separately before sharing the app. No public service,
    signed installation, API credit or clinical validation is bundled.
