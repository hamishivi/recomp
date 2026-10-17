> Version 1.5 adds a separate DXA log and upgrades diary schema to 4. See [DEXA.md](DEXA.md) and the current verification report. The release-specific details below describe earlier versions.

# Recomp 1.3 — Body measurements & maintenance

**Interface update in 1.4:** see [DESIGN.md](DESIGN.md) for the new appearance and navigation. Food estimation is now **Today → Estimate**; food-day confirmation is **Review complete day**; measurement Health controls are inside **Body → Apple Health measurements**. The implementation and safety details below are retained.

> Version 1.3 adds scale/location tags. Read [SCALES-LOCATIONS.md](SCALES-LOCATIONS.md) for the current within-scale estimator and migration rules.

## First things to try

Open the updated `Recomp.xcodeproj` in Xcode and run a Debug iPhone simulator build. The project remains unsigned source; the native iOS build has not been verified in this environment.

**No AI server or API key is needed for these new features.** Photo/text food estimates still use the existing optional server from version 1.1.

1. Open **Body → Log measurements**. Add weight, body-fat percentage and/or tape measurements. Fill only what you measured. For body fat, enter **19 for 19%**, not `0.19`. Choose kg/cm or lb/in; stored values remain kg, percentage points and cm.
2. Open **Maintenance → Explore example trends** to preview stable weight, excessive loss/gain for recomp, incomplete logging, a sudden weight spike, and a smaller waist, and two scales with different baselines. These are labelled **synthetic, read-only examples**. Nothing in this screen is written to the diary or Apple Health, and there is no Apply button.
3. For your real data, log food as before. In **Today**, select the appropriate date, scroll below the food diary and use **Review and mark day complete** after all food and drinks are included. Include alcohol, snacks, oil and sauces. Today's complete day only becomes eligible tomorrow.
4. Keep regular, comparable weigh-ins. The engine needs **21–42 consecutive complete intake days bracketed by weigh-ins**, at least 3 weigh-in days per week in aggregate, with no gap longer than 4 days. The Maintenance screen shows what is missing. A missing/excluded food day breaks the run; targets and averages are never substituted for missing intake.
5. In **Maintenance → sliders button**, enable adult fitness suggestions and review the goal/protein/fat preferences. Suggestions are off initially; learned estimates still work. Recomp is the default goal. Your starting values remain **2,500 kcal, 170 g protein, 285 g carbs, 75 g fat**, with a separately labelled **2,700 kcal maintenance guess**. The guess is never displayed as learned data.
6. When warranted, a recommendation shows the reason and before/after macros. **Review target change → Apply reviewed targets** is required to change them. Changes to targets are recorded in an audit history.

## Body measurements

Weight, body-fat percentage, waist, hips, chest, neck, upper arm, thigh and calf are supported. Each reading has a timestamp, editable value, optional method/device, notes and a local “exclude from trends” flag. Put left/right and the exact tape location in the notes; left/right limb values are not separate metric types. Use the same method and site for comparable history.

The new Body tab shows 30/90/180-day charts and editable local history. The existing Trends weight chart now includes local weights, not just Health readings. Charts use separate per-scale/method daily medians; the weight Trends chart also displays a seven-calendar-day average of available daily medians. No missing day is imputed, and nothing is inferred from a photo of your body.

Input ranges only catch gross unit/typing errors; they are not “healthy” measurement ranges. Body-fat readings are stored as reported, never used to calculate a precise muscle/fat gain or to alter calories. Body composition devices and methods are not interchangeable.

### Apple Health

Go to **Body → Connect measurements** for a separate, opt-in permission request to read/write **weight, body-fat percentage and waist circumference**. Those types exist in HealthKit. The other tape measurements, method/notes and maintenance estimates stay local. Connecting queues existing local supported readings for export, not just future entries. You can grant each permission separately.

- Weight uses kg; waist uses cm; **19% is converted to `0.19` with HealthKit's percent unit**, then converted back on read.
- Edits reuse stable per-record/per-metric identifiers and increasing versions. Failed/denied writes and deletions remain queued. Foreground/open, edits and manual sync trigger work; background delivery is not implemented.
- Deletes match both the Recomp sync ID and Recomp's Health source. The code does not delete other apps' samples. A completed authorization dialog does not prove read/write permission. Empty reads can mean no data or no permission.
- Known Recomp exports are deduplicated against local records and deletion tombstones. For daily trend calculations, local readings take priority over imported values for the same metric/scale/day. An excluded local reading does not silently reappear through an imported duplicate that day. Raw imported readings can be hidden in Recomp and restored; edit them in their source app or Health.
- Measurement reads request up to 180 days of available history; actual readable coverage may be less. Pausing body sync leaves local data and existing Health samples intact. Nutrition-only Health access can still read weight under its existing permission; body fat and waist require the Body connection.
- Exclusion is a Recomp analysis flag, **not** deletion or exclusion inside Apple Health. The entered measurement is still exported when the corresponding permission is enabled. Notes and measurement methods are not exported.
- As before, deleting a Recomp-owned sample inside Apple Health does not delete its local record. A stored export receipt is not continuous proof that the sample still exists. Make edits/deletions in Recomp for its records.

## What “maintenance” means here

The estimate is a transparent **short-window energy-balance heuristic**, not a measured metabolic rate or a clinically validated model:

```
estimated average maintenance (kcal/day)
    = mean confirmed intake
      - 7,700 × robust weight trend (kg/day)
```

For example, consistently eating 2,500 kcal while the fitted trend loses 0.2 kg/week would imply approximately 2,720 kcal/day before rounding and uncertainty. This example is illustrative, not a calculation from your actual logs.

The algorithm gives each scale/day one median and fits the median of pairwise slopes separated by at least 7 calendar days **within the same scale** (a stratified Theil–Sen-style heuristic). It fits separate baseline offsets for internal residual checks; it never calibrates stored readings. See SCALES-LOCATIONS.md for eligibility and untagged-data rules. It uses the matched morning-to-morning interval: the final weigh-in date's food is **after** the end boundary and is not included. Weighing under comparable morning conditions is important; the app does not correct for a meal eaten just before weighing.

The coefficient is not exact: scale changes may reflect water, gut contents, fat or lean tissue. Recomposition can change stored energy with little scale change. The result is an average for the observed window, not an instantaneous measure of today's expenditure. The app is **not an implementation of the NIH dynamic weight model**, does not fit adaptive thermogenesis, and does not predict long-term weight loss.

### Displayed sensitivity range

Results are rounded to 50 kcal. The range is a deliberately labelled sensitivity illustration, **not a confidence interval or a validated error bound**. It adds:

- 10% of average intake, increasing to 20% as the fraction of estimated calories rises;
- variability in the middle half of eligible weight-trend slopes;
- sensitivity to changing the 7,700 coefficient by 2,000 kcal/kg;
- a minimum margin of 150 kcal/day.

These allowances are **design assumptions**. They do not establish that your true expenditure lies inside the range. Systematic underlogging, restaurant estimates, fluid shifts and body recomposition can push it outside. Imported nutrition's calorie portion is treated as estimated for this calculation.

Workout calories are not added to the result. The model attempts to infer total expenditure from intake and weight; adding exercise calories again would double-count that conceptual contribution. It does not automatically read or interpret workouts, steps, strength, illness or creatine use. Use day notes/exclusions and your own judgement for changed circumstances.

## Recommendation rules

All thresholds in this section are conservative **product heuristics**, not clinically validated prescriptions or individualized safety thresholds.

The default recomp goal accepts a weight trend from roughly −0.35% to +0.15% per week. Stable weight does **not** trigger a calorie cut. At least two comparable waist readings in both the first and final week, using the same scale/location and method/source, can support holding calories when waist decreases and weight is stable or increasing slowly (up to +0.3%/week). This does not prove muscle gain.

Optional goals use other modest bands: maintenance ±0.15%/week, gentle loss −0.4% to −0.1%/week, and slow gain 0% to +0.25%/week. The app does not equate weight gained with muscle or weight lost with fat.

A calorie suggestion requires agreement between the full and recent two-week trends, recent intake reasonably close to the configured target, sufficiently stable/recent data, and no target/goal change within 14 days. Each proposed change is limited to **100–150 kcal/day**, and you must apply it. No compensation is prescribed for a single over-target day. After a reviewed change, the next target suggestion is held for at least 14 days.

Protein is based on recent median weight and your preference (default 2 g/kg, rounded to 5 g). Fat uses your chosen grams with a 0.6 g/kg product guardrail. Remaining calories go to carbohydrate. Proposed macro calories agree with the calorie target within rounding. No separate exact carb target is treated as mandatory.

Rapid weight changes over 1%/week, major trend disagreement, noisy data, very low/implausible implied values, or proposed targets outside the tool's conservative operating range block proposals. This is **not** an assessment of energy availability, a guarantee of safety, or a substitute for a clinician. Guidance is for adults pursuing general fitness, not pregnancy/breastfeeding, eating-disorder treatment, or medically prescribed diets.

## Complete-day snapshots and corrections

Confirmation stores that day's reviewed nutrition total, whether additional Health nutrition was included, the estimated-calorie share, date, timezone and optional notes/exclusion. These are intentional snapshots: Apple does not expose read denials, and a day of imported nutrition cannot automatically be assumed complete.

Changing/deleting/moving local food invalidates the affected day confirmations. Changing a photo estimate and saving the meal uses the same invalidation path. Changes made later in another food app do **not** automatically alter historical confirmations: open that date, refresh, check duplicates and confirm again. The day card warns when its current displayed totals differ from the confirmed snapshot. Switching the “include Health nutrition” display setting does not rewrite historical confirmations.

All food days in an analysis must have the same time zone as the current analysis calendar. Old confirmations made elsewhere are retained but not merged into a new time-zone run. This is conservative during travel. Day arithmetic uses calendar days, including daylight-saving transitions, rather than assuming every day lasts 24 hours.

## Updating and data retention

Use the **same development team and bundle identifier** when running 1.3 over your existing installation. Do not uninstall first. Export data before updating. Version 1.0/1.1/1.2 JSON is decoded into schema 3 with defaults for missing fields, preserving food entries, saved foods, AI breakdowns, targets and existing sync queues. The migration is covered by portable tests; a physical-device upgrade has not been tested.

After the new version saves schema 3, old app versions will not read the diary. Do not downgrade over your only copy. All local logs use the existing atomic, protected, backup-excluded diary file. Uninstalling loses local data. There is no full restore/import workflow.

Settings has separate CSV exports for food, local measurements and analysis history (confirmed days, maintenance snapshots, before/after target changes). Measurement CSV includes current scale/location IDs and labels. CSV is readable outside the app and is not a full backup/restore format. Imported raw Health readings are not exported in these local CSVs, although confirmed-day totals may include Health nutrition that you reviewed. One maintenance snapshot per day is retained for up to 365 days; old snapshots are an audit trail and are not automatically revalidated after edits to old data.

No new records from this chat or your prior ChatGPT Health connection are embedded in the app. Starting targets/guess are preferences, not measurement history. All maintenance analysis runs locally and is not sent to the photo server. The unchanged photo-estimation service only receives selected meal content after confirmation.

## Verification

See `Verification/BUILD_STATUS.md` and its logs for actual results. To run the checks:

```bash
swift test
./scripts/check-store.sh
(cd Server && node --test)
# On a Mac with Xcode, also perform the native simulator build:
./scripts/check.sh
```

The coordinator harness uses labelled test doubles instead of Combine/HealthKit. It checks the production coordinator's typing, local persistence and control flow; it does not establish real HealthKit semantics, permissions or native UI correctness.

Native Xcode compilation, camera/photo estimation, real HealthKit writes/reads and real-device migration remain unverified. The included `.github/workflows/check.yml` can perform a macOS build when you put the project in a repository and run the workflow; it was not run for this delivery.

## Primary references

Reviewed September 18, 2026. These sources support principles/APIs, **not validation of this particular app or its thresholds**.

- Hall et al. (2011), dynamic energy balance and bodyweight: https://pubmed.ncbi.nlm.nih.gov/21872751/
- NIDDK, research behind its dynamic Body Weight Planner: https://www.niddk.nih.gov/research-funding/at-niddk/labs-branches/laboratory-biological-modeling/integrative-physiology-section/research/body-weight-planner
- Jäger et al. (2017), ISSN protein and exercise position stand: https://pubmed.ncbi.nlm.nih.gov/28642676/
- Frija-Masson et al. (2021), smart-scale body composition accuracy: https://pubmed.ncbi.nlm.nih.gov/33929337/
- Apple, body-fat quantity type: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodyfatpercentage
- Apple, waist-circumference quantity type: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/waistcircumference
- Apple, sync identifiers: https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- Apple, percent-unit convention for percentage quantities: https://developer.apple.com/documentation/healthkit/hkapplewalkingsteadinessclassificationforquantity
