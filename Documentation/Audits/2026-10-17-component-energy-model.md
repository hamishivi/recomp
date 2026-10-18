# Component energy model

Research and implementation review, 17 October 2026.

Recomp now estimates **resting energy + everyday movement + net exercise + digestion** when suitable resting-energy input is available. This makes the accounting and assumptions inspectable. It does **not** establish that the app measures an individual's expenditure accurately, or that it outperforms a wearable. Software tests establish arithmetic and behavior, not physiological validity.

## Resting metabolism

The automatic equation is Cunningham's 1991 prediction, `REE = 370 + 21.6 × fat-free mass in kg`. At 60 kg FFM, this gives 1,666 kcal/day. It predicts resting expenditure; an app cannot establish the controlled conditions needed to label a reading measured BMR. It is distinct from Cunningham's earlier `500 + 22 × lean mass` equation. The original paper describes a population prediction rather than an individual metabolic test. [Cunningham 1991](https://doi.org/10.1093/ajcn/54.6.963), [Cunningham 1980](https://pubmed.ncbi.nlm.nih.gov/7435418/).

Following the user's preference, the app uses existing body composition and an optional manual override. No age, height or equation-sex fields were added. Input precedence is:

1. A valid manual resting-energy value recorded by the selected time. A separate declaration distinguishes user-entered indirect-calorimetry results from other manual values.
2. The newest suitable body-composition estimate from the previous 90 days, using reviewed whole-body DXA FFM or paired weight/body-fat readings.
3. The existing maintenance/activity fallback when neither is available, explicitly described as lacking resting-energy input.

DXA lean soft tissue alone is insufficient: FFM includes bone mineral. The existing DXA mapping accepts explicit unambiguous whole-body FFM or lean soft tissue plus bone mineral content, rejecting conflicting totals, regional values and ambiguous “lean mass.” A DXA report's calculated RMR is not automatically treated as measured metabolism. Scale-based FFM uses `weight × (1 − body-fat percentage/100)` with contemporaneous readings from the same source, method and scale location. The code never multiplies today's weight by an unrelated old body-fat reading. A same-day tie favors reviewed DXA. These checks do not remove the underlying measurement error of DXA or bioimpedance.

The 90-day freshness limit and seven-day pairing window are product rules, not validated physiological cutoffs. A manual value remains until changed; its date is retained. Resting energy is spread evenly across actual elapsed seconds, including 23/25-hour daylight-saving days. Sleep does not receive a separate arbitrary calorie discount.

## Everyday movement and exercise

NEAT includes movement beyond purposeful exercise. In a chamber study of 177 people, spontaneous activity explained substantial expenditure variation even after body size was considered. Steps therefore cannot represent all everyday movement. This supports distinguishing step-based walking from an explicitly provisional allowance for standing, chores and fidgeting; it does not validate a particular allowance for an individual. [Ravussin et al. 1986](https://jci.org/articles/view/112749).

Non-workout walking retains the app's coarse net coefficient, `steps × weight kg × 0.0004 kcal`. Terrain, stride, speed, carrying loads and gait are not measured. The default untracked allowance is **150 kcal per 24 hours** and usual forecast steps are **5,000**. Both are editable assumptions, not recommendations or research-derived personal estimates.

Workout gross energy retains the existing activity-kind/pace MET bands and approximate `MET × kg × active hours` conversion. Net exercise subtracts the chosen resting rate for the same active duration, floored at zero. Overlapping workout rates use the largest rate instead of adding duplicates. Steps during any recorded workout interval do not add walking energy; the non-step allowance is also removed during its active fraction. Paused duration is handled proportionally because exact pause timestamps are unavailable.

The 2024 Adult Compendium is a useful activity reference, but its authors warn that neither standard nor corrected METs replace direct energy measurement. Its adult table covers ages 19–59; a generic activity category is not a personalized intensity measurement. Recomp does not claim to implement a validated “corrected MET” procedure. No Apple active/resting-calorie samples are added. [2024 Compendium](https://pacompendium.com/adult-compendium/), [authors' explanation of MET limits](https://pacompendium.com/corrected-mets/).

## Digestion

The thermic effect of food varies by nutrient. Published ranges are approximately 20–30% of protein energy, 5–10% of carbohydrate energy and 0–3% of fat energy. Recomp uses their midpoints: 25%, 7.5% and 1.5%. Energy with no usable macro attribution receives a provisional 10% estimate. Alcohol has no separate field, so its different thermogenesis is not modeled. These coefficients are approximations. [Westerterp 2004](https://pmc.ncbi.nlm.nih.gov/articles/PMC524030/).

Reported calorie/macro discrepancies are bounded: macro-derived thermogenesis is scaled down when macro energy exceeds reported calories; remaining unattributed calories receive the fallback fraction. Digestion is distributed uniformly over eight hours after food. Research supports a response lasting several hours, but **the uniform eight-hour kernel is an implementation heuristic**, not a validated time course. Contributions crossing midnight are divided between days rather than charged twice.

Local meals and their own Health exports are not counted twice. External Health nutrients are combined by source/day before TEF calculation, then distributed across calorie timestamps. Health's separate nutrient samples do not reliably identify individual meals, so this is coarser than local meal timing.

When confirmed food coverage is incomplete, burn so far uses the larger of known digestion and a time-proportional usual-intake allowance. It does not silently treat unlogged meals as fasting. Typical intake comes from at least seven elapsed days of conflict-free confirmed food, otherwise food targets. The extra allowance is shown separately. Complete confirmed coverage removes that floor. The forecast uses the larger of remaining known digestion and the usual-intake remainder, avoiding an additive duplicate allowance.

## Learning from the diary

The existing maintenance estimator supplies a total-expenditure anchor only after its own food/weight gates pass. Its comparable-scale trend, completeness checks, uncertainty range and manual target review remain intact. The component model requires an anchor no more than four days old and a range no wider than 60% of its estimate. It additionally requires seven confirmed food days and seven recent activity days, each with at least eight hours of interval records, within the previous fourteen calendar days. Daily step summaries alone cannot invent hourly coverage. Recorded hours are only a coverage proxy, not proof of device wear.

With those gates, the residual is `maintenance − resting − typical digestion − typical net walking − typical net exercise`. It replaces the untracked allowance, with adjustment for time already occupied by exercise. Negative residuals, residuals exceeding half the anchor, or implausibly little non-workout time pause calibration and retain the provisional allowance. These thresholds are conservative engineering rules and have not been clinically validated.

The residual is **not independently measured NEAT**. It can absorb food-log error, resting prediction error, missed activity and metabolic adaptation. Careau et al.'s doubly labelled water analysis found variable energy compensation across people; its population average is not a defensible fixed exercise discount for this user. Recomp therefore does not apply a blanket 28% deduction. [Careau et al. 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8551017/).

The underlying retrospective maintenance calculation still approximates tissue-energy change using 7,700 kcal/kg. Water, glycogen, body composition and adaptation limit that approximation. Hall et al.'s dynamic modeling shows why a fixed energy-per-weight rule should not become an exact long-term weight-loss forecast. No such forecast was introduced. [Hall et al. 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/).

## Chart, persistence and practical accuracy

The solid curve ends at the exact current cutoff; future movement/digestion appears only in the dashed forecast. The breakdown exposes RMR, everyday movement including its allowance, exercise above rest and TEF including any intake allowance. It identifies the resting source and calibration status. Missing resting input retains the existing fallback with a clear explanation. Enabling this model does not change food targets or automatically add exercise calories to an eating allowance.

Settings are validated, saved locally, included in backup and sync, and default safely when loading older diaries. No new Health writes or demographic collection were added. Future, excluded or stale composition is rejected. Numerical input limits are parser safeguards, not recommended physiological ranges.

There is no calibrated individual confidence interval. A more elaborate formula can still be wrong if its inputs are wrong. To establish individual accuracy would require independent measurements, such as resting calorimetry and free-living total expenditure measured by doubly labelled water, followed by a prospective comparison. Fitting the model to the same food/weight data is calibration, not independent validation. The useful improvements here are explicit components, clearer assumptions, safer missing-data behavior and consistent accounting.

Implementation: `Recomp/Core/EnergyExpenditure.swift`, `Recomp/Services/DiaryStore.swift`, and the Energy model settings/chart views. Synthetic arithmetic, persistence and native UI verification are recorded under `Verification/ComponentEnergy`.
