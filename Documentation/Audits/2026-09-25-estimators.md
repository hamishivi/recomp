# Calorie and maintenance audit — September 25, 2026

## Changes

### Daily expenditure

The intraday calculator previously allocated 100% of maintenance to baseline expenditure and then added exercise, steps and 10% of logged food calories. This double-counted costs already represented in maintenance; walking/running could also be counted in both workout and step estimates. A universal 28% exercise compensation factor and a fixed circadian pattern were presented as individualized physiology.

The chart now shows an explicitly labelled linear expenditure pace from the maintenance rate. Activity remains visible as context without increasing the calorie budget. It does not claim to know today's departure from average expenditure or the timing of metabolism. Daily step snapshots and identical workout IDs are deduplicated, and workouts overlapping midnight remain visible on both days.

Maintenance is expressed per 24 elapsed hours. A civil day spanning a daylight-saving transition is therefore assigned 23/24 or 25/24 of that rate. The chart ends at the actual next midnight, and the summary and historical expenditure helpers use the same convention.

Weight summaries now ignore excluded/invalid measurements and compare readings only from the latest scale/source when no learned trend is available.

### Meal calories

Both AI routes now explicitly handle kJ-to-kcal conversion, a single serving multiplier applied to every nutrient, recipe yield, edible/drained weight, retained cooking fat, alcohol energy and total versus net carbohydrates. These are instructions to the estimator, not a claim that AI-extracted arithmetic or portions have been independently verified.

The review screen flags individual components with calorie/macro discrepancies above both 50 kcal and 20% of stated energy. These are review thresholds, not nutritional error bounds. Values are preserved: fibre, alcohol and label conventions can legitimately differ from 4/4/9 arithmetic. Checking each component avoids opposing errors cancelling in meal totals.

Locked items now retain their original nutrition and evidence text during text-only refinements without attributing old evidence to a missing or different current photo. Invalid photo citations from a new response are still rejected.

### Maintenance

The broad coordinator checks also exposed automatic day completion: any past food entry was treated as complete intake, existing confirmations could be overwritten with local-only totals, and confirmations without local meals were deleted. This could remove reviewed Health nutrition or learn from a partial log. That behaviour is removed. The existing day-review card is restored in both Today layouts so users can confirm complete food coverage. Saving a partial past meal does not certify its day, and reviewing maintenance does not rewrite historical food snapshots.

The engine now enforces its stated 42-elapsed-day limit. When legacy whole-day food snapshots move the analysis boundaries inward, the weight fit is recomputed using that interval. Weight counts, gap checks, same-scale span and recent trends use the recomputed data. Boundary gaps are included in coverage checks.

The sensitivity range uses the larger of pairwise slope variation and disagreement between recent and full-window trends. Thus an apparently smooth overall fit cannot alone imply a narrow range during a trend change. The range remains a heuristic sensitivity illustration, not a confidence interval.

The existing 21-day minimum, complete-food-coverage requirement, same-scale comparisons, 14-day adjustment cooldown, manual target approval and conservative target bounds remain. No diary schema migration is required. Older automatic and manual confirmations were not stored with distinguishable provenance, so they are preserved rather than guessed at or deleted. Review previously auto-completed days again; the repair cannot reconstruct missing food.

## Method limits and references

The maintenance calculation remains `mean intake − 7700 × weight slope (kg/day)`. It is a short-window energy-balance approximation, not a long-term weight forecast. Sparse data, systematic underlogging, changes in water/glycogen and recomposition can bias it. The refitted legacy window can require short extrapolation from the nearest weigh-ins to whole-day food boundaries; sparse boundary coverage is checked rather than inventing meal timestamps.

A dynamic physiological model would need additional validated inputs and calibration; replacing this equation with an elaborate uncalibrated model would not establish better accuracy. The NIDDK model explicitly represents glycogen and fluid changes: [Hall model appendix](https://www.niddk.nih.gov/-/media/Files/BWP/Hall_Lancet_Web_Appendix.pdf) and [Body Weight Planner](https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner).

Serving-size scaling follows [FDA label guidance](https://www.fda.gov/food/nutrition-facts-label/how-understand-and-use-nutrition-facts-label). Alcohol contributes energy outside protein/carbohydrate/fat totals; the [FDA nutrition label explainer](https://www.accessdata.fda.gov/scripts/interactivenutritionfactslabel/assets/InteractiveNFL_WhatsOnTheNFL_October2021.pdf) includes alcohol among energy sources. These references support principles, not validation of this application's thresholds or AI estimates.

## Validation

The original 405 core tests passed before changes; one explicitly encoded the old double-counting behaviour and was updated. Added regressions cover window matching, the 42-day cap, trend sensitivity, daylight-saving transitions, duplicate step snapshots, calorie review without rewriting labels/alcohol, historical photo evidence and excluded/different-scale weight summaries.

`./scripts/check.sh` completed successfully (exit 0) with Xcode 27.0 and the iOS 27.0 simulator:

- 413 core tests passed in both Debug and Release.
- 68 server tests passed.
- All source contracts and coordinator, persistence, backup, network, estimator, composer, startup, audit and travel harnesses passed.
- 417 native unit tests and all 13 UI tests passed.
- Native Debug test build and Release simulator app/widget build succeeded.

Full output: [check.log](../../Verification/Estimator-Audit-2026-09-25/check.log). Native result bundles and UI screenshot attachments: `.native-results/20260925-172435-17514/`.

Live AI accuracy, real HealthKit permissions/synchronization and physical-device behaviour require separate testing; synthetic tests do not establish those properties. No app was installed on a physical device and no live AI request was sent.
