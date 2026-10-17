> Version 1.5 adds a separate DXA log and upgrades diary schema to 4. See [DEXA.md](DEXA.md) and the current verification report. The release-specific details below describe earlier versions.

# Recomp 1.3 — Scale and weigh-in location tags

**Interface update in 1.4:** see [DESIGN.md](DESIGN.md) for the new appearance and navigation. Food estimation is now **Today → Estimate**; food-day confirmation is **Review complete day**; measurement Health controls are inside **Body → Apple Health measurements**. The implementation and safety details below are retained.

This is an **unsigned Xcode source project**, not an installable App Store app. Native iOS compilation, UI behaviour and real-device HealthKit integration have not been verified here. The portable tests and coordinator harness are described in `Verification/BUILD_STATUS.md`.

## Use it

1. Open **Body → Log measurements → Scale / location**. Choose **Home** or **Girlfriend’s**, or tap **New scale / location** to create another. One label should identify one physical scale, not several scales at the same address. Every measurement saved in that check-in receives the selected tag.
2. New check-ins preselect the last tag you used when saving a new check-in. **Check it when switching homes.** Nothing uses GPS or automatically detects where you are. The initial selection is Untagged. Editing an older entry does not change the next-entry default.
3. To tag an old local reading, choose **Body → history → Edit**. Imported Apple Health readings have a **Tag** button instead. Tagging an import adds a local annotation to that sample ID; it does not copy the reading, change its value or write a new Health sample. Separately imported weight and body-fat records need separate tags.
4. The **Scale / location** filter in **Body** and **Trends** offers all scales, one scale or untagged only. All-scales mode uses separate curves, never one line connecting readings from different scales. The Trends seven-day averages are also calculated separately per scale. The latest headline is the latest individual reading and identifies its scale—not a cross-scale average.
5. Open the **tag button in Body** to manage scales. Rename updates the label throughout current history without changing IDs or measurements. Archive removes a scale from new-entry choices and clears it as the last-used default, but keeps its history, chart filter and maintenance selection. Restore is reversible. Replacing a physical scale should create a **new label**, rather than reusing the old scale's history under a new name.

The tag also works on body-fat and tape-measurement records. Body-fat and tape chart series additionally separate differing method labels. A weight tag identifies its scale regardless of free-text method notes.

## Maintenance from two scales

**Maintenance → Weigh-in scales** defaults to **Automatic · same-scale comparisons**. Select Home or Girlfriend’s here to use only that scale; the engine never silently falls back to another if the selected one has insufficient data. Chart filters are separate viewing preferences and do not change the maintenance selection.

For automatic analysis, the engine calculates daily medians within each scale and uses only weight differences between readings from the **same scale**, at least seven calendar days apart. It takes the median of those pairwise slopes across the qualifying series. Frequently measured scales contribute more pairs; pairs never cross scales. A separate constant baseline is fitted for each series for internal residual checks. The most recently measured qualifying series is the weight reference, shown in the report; ties use the number of days and then stable ID. This is not a calibration of your scales, and **stored weights are never rewritten or offset-adjusted**.

For example, if a synthetic stable-weight history consistently reads 85 kg at Home and 86.5 kg at Girlfriend’s, switching locations does not create a gain/loss slope in this model. A real shared loss trend still changes the estimate. These behaviours are tested with daily alternation, week-long alternating stays and multiple constant offsets.

### Coverage and safeguards

- Existing requirements remain: 21–42 consecutive complete food days bracketed by usable weigh-ins; at least three distinct weigh-in days per week in aggregate; no gap longer than four days across the combined usable history. Multiple scales on the same day count as **one** coverage day.
- Each included scale/source series needs at least three weigh-in days spanning seven days. At least one series must span 21 days. Short disconnected visits do not establish a long-term trend merely by connecting their raw weights. A one-off new-scale reading is shown in history but does not extend the analysis interval or change its slope.
- When automatic analysis has tagged weights, untagged weights are excluded and the report says how many. **Tag old mixed-scale readings before using them.** When all relevant readings are untagged, the legacy path assumes one scale per method/source and displays an explicit warning. The app cannot infer which physical scale an untagged entry came from; an importing app can itself combine multiple scales. Tagging remains necessary for correct separation.
- When scales' within-scale trends disagree, or there is too little recent comparable history, the engine withholds target-change suggestions. Agreement is a product heuristic, not proof of accuracy. Existing small-change limits, food completeness checks, cooldown and review-before-apply remain.
- Known constant differences cancel in same-scale differences; drifting calibration, different weighing conditions, changing hydration, wrong tags or different nonlinear trends need not cancel. This method does not identify which scale is correct. The calorie estimate remains an unvalidated energy-balance heuristic, not a measured metabolic rate. The displayed sensitivity illustration is not a statistical confidence interval.
- Body-fat values still do **not** enter the maintenance calorie equation. Waist support now respects scale/location and method groups as well; a change of location alone cannot establish a comparable waist reduction.

The engine's scale-specific thresholds are conservative design choices, not clinically validated recommendations. For general weighing consistency, the NHS recommends the same scales and location and comparable conditions: [NHS — How to record your weight](https://www.england.nhs.uk/long-read/how-to-record-your-weight/) (checked September 18, 2026). That guidance does not validate this algorithm.

## Preview without logging fake measurements

Open **Maintenance → Explore example trends → Two scales, different baselines**. This is a synthetic read-only example using alternating week-long stays. Nothing is inserted into your diary, sent to Health, or applied to your targets. It is separate from your actual measurements.

## Apple Health and privacy

Weight, body-fat and waist numeric values continue to use the existing optional Health integration. **Scale/location labels and imported-sample annotations stay in Recomp**, alongside the protected local diary. They are not included in HealthKit metadata or sent to the photo-estimation service. No location permission, GPS lookup, geofencing, network service or API key is needed for tagging or maintenance analysis. No actual measurements from this conversation are seeded.

Editing a local reading's tag saves the same record ID with a new version; if body sync is enabled, its unchanged numeric value follows the existing replacement path rather than intentionally creating a duplicate. Retagging an imported reading never writes to its source. A source app deleting and recreating a Health sample gives it a new sample ID, so its old local annotation cannot automatically follow it. Tags cannot be reconstructed by reinstalling and reimporting Health samples.

## Updating, exports and persistence

Export before updating, keep the **same bundle identifier and development team**, and run the new project over the existing installation. Do not uninstall to update. Native upgrade testing is still outstanding.

Schema 1 and 2 diaries migrate to **schema 3**, preserving foods, estimates, measurements, receipts, queues, targets and audit history. Existing measurements remain **Untagged**; no guessed location is assigned. Starter names do not create any measurements. Schema 3 records the scale catalogue, optional per-reading tag IDs, next-entry default, maintenance scale selection and local imported-sample annotations. Archived IDs remain valid references. The old app versions will not read schema 3—do not downgrade over your only copy.

Local measurement CSV exports now include `scale_location_id` and `scale_location`; these reflect current label names and use the existing formula-safe CSV escaping. Imported Health readings/annotations are not included in that local-measurement CSV. Analysis CSV records scale context for new maintenance snapshots. Earlier snapshots remain an audit trail of the old model, not recalculated results; today's snapshot is recomputed or removed when edits make today's analysis insufficient.

All local data, including tags, is lost on uninstall. Existing CSV exports are not a full backup or a restore/import mechanism. No multi-device tag sync or restore workflow is implemented.

## Verification and on-Mac checks

```bash
swift test
./scripts/check-store.sh
(cd Server && node --test)
# macOS + Xcode is required for the native simulator build:
./scripts/check.sh
```

Core tests cover constant-offset invariance, preserved common slopes, daily and weekly alternating scales, same-day separation, unique-day coverage, sparse/disconnected histories, conflicting trends, untagged policies, one-scale selection, CSV escaping, migration and identity preservation. The coordinator harness uses test doubles and checks actual DiaryStore persistence and control flow. Neither establishes native SwiftUI/Charts/HealthKit behaviour.

On your Mac/iPhone, additionally test: changing the default when switching homes; editing and tagging history; importing/tagging without duplicate Health samples; renaming and archiving; filtered and all-scales charts; body-fat/tape series; the read-only two-scale demo; same-ID in-place upgrades; and export contents. The optional photo server is unchanged by this feature.
