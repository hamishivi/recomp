# Activity-aware expenditure — September 25, 2026

## Behavior

The Today chart now estimates **background expenditure + walking outside workouts + net workout expenditure**. It does not read Apple's resting-energy, active-energy or workout-calorie estimates. Health supplies only existing read-only inputs: steps and workout timestamps, duration, type and optional distance. Body weight comes from the latest comparable daily weight series, respecting exclusions and avoiding future measurements. No available weight means an explicitly labelled 75 kg fallback.

Food and exercise records are unchanged. No diary migration or additional Health permission is required. Food targets and the long-term intake/weight maintenance estimator are unchanged.

The background includes resting expenditure, digestion and movement the activity model cannot observe separately. Calling this an individually measured BMR would be misleading. Digestion stays within the background rather than being added again for each meal.

## Calibration

For the 14 calendar days before the selected day, compute net activity with the same model used for today. Only completed days containing available step data qualify; absent days are not treated as zero. At least seven qualifying days are required. Each day's activity is normalized to 24 elapsed hours before averaging, including DST days.

`background kcal/24 h = maintenance estimate − average modeled activity kcal/24 h`

A day with typical activity consequently returns maintenance; additional or reduced activity increases or decreases that day's estimate. Maintenance can be learned from intake and weight, or the user's starting maintenance when evidence is insufficient.

If history is inadequate or average activity exceeds half of maintenance, use a **labelled provisional** background of 80% of maintenance, reserving 20% for typical activity. This allocation is a product heuristic, not an individually validated resting-metabolism equation. The model does not let implausible activity history drive the background negative.

## Activity estimates

- Walking outside workouts: `steps × weight kg × 0.0004`. This is a coarse net-energy heuristic (about 30 kcal per 1,000 steps at 75 kg), not a measurement of stride, gradient, load or efficiency.
- Workouts: `(MET − 1) × weight kg × active hours`. Subtracting one MET avoids adding resting expenditure a second time. Active duration is distributed across the recorded start/end span to account for pauses.
- Running uses distance/duration pace bands where available and a generic jogging assumption otherwise. Strength training uses 3.5 MET, walking 3.8, hiking 5.3, cycling/swimming 6, yoga 2.3, and unknown activities 3. These defaults are approximate; the generic cycling/swimming/unknown choices are deliberate coarse assumptions. Very fast running is capped at 12 MET in this model.
- The [2024 Compendium running table](https://pacompendium.com/running/) informs the pace bands and jogging default. Its [conditioning table](https://pacompendium.com/conditioning-exercise/) informs the general strength/yoga values. These population values do not establish individual accuracy. The [Compendium publication](https://pmc.ncbi.nlm.nih.gov/articles/PMC10818145/) discusses its use and limitations.

Hourly step counts come from HealthKit's merged statistics, rather than summing raw phone/watch samples. Timing is approximated uniformly within each returned bucket; the current bucket ends at the read time. Steps during a workout do not contribute a separate walking estimate. Overlapping workout records use the largest concurrent net rate rather than adding rates, so overlapping Strava/Watch copies cannot double the session's expenditure. Duplicate step buckets also use the largest concurrent rate. Nonoverlapping duplicate sessions with erroneous timestamps still require user review in Activity.

Older callers with only daily step totals get a coarse distribution across the observed day. Sparse readings or partial device wear can still undercount activity or bias calibration; absence cannot reliably be distinguished from inactivity. The app does not claim to outperform a wearable or measure fat oxidation.

## Curve and forecast

The background accumulates with elapsed time. Activity accumulates during recorded workout spans and step buckets. The chart includes the exact current instant, so the marker and header agree. Future activity is projected at the typical average rate and is never included in expenditure so far. The dotted reference shows average maintenance, separate from the dashed activity-adjusted day forecast. With no activity data for the day, the chart explicitly falls back to maintenance pace instead of claiming inactivity.

The Today display separates background, walking and workout calories, indicates provisional/history-calibrated status, and identifies the forecast. Expenditure is energy used, not a claim about grams of body fat burned. Energy expenditure's resting, activity and digestion components are described in the [Dietary Reference Intakes for Energy](https://www.ncbi.nlm.nih.gov/books/NBK591031/).

## Verification

438 core tests passed before the full gate, including new tests for overlapping/duplicated workouts, duplicate step buckets, partial step/workout overlap, paused workouts, typical/busy/quiet-day calibration, missing and future data, the exact now marker, forecast separation, midnight-crossing workouts, DST and implausible history. The real-store persistence audit passed all 38 checks. The complete `scripts/check.sh` pipeline passed: 438 Debug/Release core tests, all coordinator/source/network/crypto harnesses, 68 server tests, 443 native unit tests, all 13 UI tests, and the simulator Release app/widget build. A signed iPhone Release build also succeeded after renewing the app/widget provisioning profiles. No new Health permissions were added.

Logs: [verification directory](../../Verification/Activity-Expenditure-2026-09-25/). Native result bundle: `.native-results/20260925-220407-56120/Tests.xcresult`.

Previously observed frame-dimension warnings in food-sheet transitions remain outside this change. Real-world individual energy accuracy has not been validated.

## Chart usability review — October 17, 2026

The previous view used dashed lines for both maintenance and forecast, drew a workout dot at every sampled point, and exposed no time selection despite retaining selection state. Past days still said “Day forecast,” and the displayed cutoff did not advance while Today remained open.

The chart now distinguishes solid estimated burn, an orange dashed forecast and a neutral dotted maintenance reference with a matching legend. Tap a time or hold and drag to inspect its cumulative estimate and difference from maintenance pace; future selections explicitly say “Forecast.” Ordinary vertical swipes still scroll the page. Completed days show an estimated day total and maintenance comparison; upcoming days show no expenditure so far. A minute timeline supplies the same timestamp to the calculator and chart.

Curve samples include activity segment boundaries as well as the quarter-hour grid and exact cutoff. Short workouts therefore retain their start/end changes in slope. Workout markers appear once per recorded start time, clipping overnight starts to the displayed day. The estimate and forecast share the exact cutoff point. These changes preserve the expenditure formula, calibration, overlap handling and daily totals.

Readouts, legends and activity labels adapt to narrow layouts and Dynamic Type. Accessibility text sizes use fewer time labels and abbreviated calorie ticks to avoid collisions. Calibration and provisional-background notes remain visible; the numeric breakdown and longer model explanation are under “How this is estimated.” Settings → Interface preview → Burn provides isolated sample activity, completed/upcoming days and the maintenance fallback.

The updated core suite passes all 442 tests in Debug and Release, including short workouts, the cutoff join, past/future days, ongoing overnight activity and selection across a repeated DST hour. All 158 interface/source checks pass. Both focused iPhone simulator UI tests pass, covering tap/drag/reset, completed/upcoming days, missing activity, model disclosure, dark appearance and the largest accessibility text size. The simulator Release app/widget build also succeeds. The exported chart screenshots were visually inspected; this does not constitute a full VoiceOver or device accessibility audit. Native acceptance results, screenshots and build logs are saved in `Verification/CalorieBurnChart/`.
