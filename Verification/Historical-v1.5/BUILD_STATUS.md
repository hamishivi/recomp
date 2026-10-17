# Verification — Recomp 1.5 DXA import

**Unsigned Xcode source project. No native Apple SDK build, simulator run or real iPhone test was performed.**

Environment: Linux x86_64; Swift 6.2.1; Node.js 22.16.0. September 18, 2026.

## Actually run

| Check | Result | What it establishes |
|---|---|---|
| Portable Swift package, Debug | 210 tests passed, 0 failures | 168 retained tests plus 42 DXA core tests |
| Portable Swift package, Release | 210 tests passed, 0 failures | Same portable suite, optimized build |
| Production DiaryStore against labelled test doubles | 61 checks passed | Local persistence/control flow, not native HealthKit |
| Server unit and HTTP tests | 42 passed | Mocked AI provider, no live call |
| Static interface/project checks | 75 passed | Source membership, retained design tokens, plists/scheme; not UI rendering |
| Swift parser across all 34 app sources | Passed | Syntax only, no native API type checking |
| Synthetic PDF fixture | Rendered and visually inspected | One-page fictional fixture, no real patient data |
| Fixture text through production parser | 8 candidates / 5 explicit total-body sites | PyMuPDF extraction on Linux, **not Apple PDFKit** |
| Retained maintenance/scale engines and Health/estimation services | Byte-identical to 1.4 | See `domain-unchanged.log` |

Logs: `core-tests.log`, `release-core-tests.log`, `store-checks.log`, `server-tests.log`, `interface-checks.log`, `source-checks.log`, `dxa-fixture-check.log`, `domain-unchanged.log`.

New tests cover original/canonical units, percentages, signed scores, lean-definition separation, invalid dates and values, per-site identities, reviewed-state validation, duplicate PDF identities, schema 3→4 migration, state round trips and failed-save protection, preserved existing data, PDF size/header/fingerprint rules, formula-safe CSV, comparison grouping/sites/dates/units, ambiguous same-day priors, non-destructive consistency warnings, parsing limits and ambiguous text, plus isolation from scale data, Health queues and maintenance calculations.

The core tests use synthetic data and do not validate nutrition or medical accuracy. The parser fixture is not evidence of compatibility with a provider's table format. The model tests inspect PDF-header/size rules but do not implement a PDF renderer; the native reader is responsible for actual PDF parsing.

## Not verified

- Native SwiftUI/Charts/PDFKit/CryptoKit/HealthKit compilation, linking or app launch.
- iPhone/iCloud Files picker permissions, file coordination, password-protected reports, PDFKit text order or image-only report behaviour.
- Sheet navigation, final-review reset, cancellation, Dynamic Type, VoiceOver or visual layout on Apple devices.
- Real provider report ingestion, OCR (not implemented), clinical interpretation (not implemented), real-world scan accuracy or calibrated scanner comparisons.
- Real Health sync, food camera, live AI responses, signing, distribution or in-place device upgrade.

## On-Mac / device acceptance checklist

1. Run `./scripts/check.sh` in Xcode's environment. Resolve native API/compiler issues, then test Debug and Release.
2. Update in place using the same team/bundle identifier; verify existing data, scale tags and pending Health queues are retained.
3. On a throwaway simulator, import `Examples/DXA-synthetic.pdf`. Open its PDF preview, find the eight labelled candidates, choose date/provider explicitly, review each site/unit and save.
4. Confirm that cancelling an import/draft saves nothing. A failed/duplicate/oversized/protected import must leave the existing draft unchanged.
5. Test a real provider PDF with selectable text and a scanned/image-only PDF. Unsupported layouts must fall back to manual entry without fabricated fields.
6. Enter body fat, kg/lb/g masses, negative T/Z scores, density to three decimal places and a regional value. Check site labels and original units after save/restart/export.
7. Modify a reviewed result/date and ensure the review checkbox is cleared. Reject a duplicate metric/site, missing provider or future date. Check that changing displayed units does not silently convert the number.
8. Compare scans with matching and different scanner groups; test same-date ambiguities, unassigned groups and unconfirmed lean definitions.
9. Import/edit/delete scans while Health is connected. Confirm no Health writes, no changes to scale points, learned maintenance, targets or cooldown history.
10. Keep a PDF, reopen it, export it, then remove retention by editing the scan. Confirm the external original remains unchanged. Export CSV and inspect the original/canonical units and formula escaping.
11. Keep only reviewed values, reopen after restart and confirm no retained PDF or full extracted text exists. Uninstall only after preserving real data; there is no backup/restore implementation.

Historical reports and logs from prior versions are not native verification of this version. The included macOS workflow was not run for this delivery.
