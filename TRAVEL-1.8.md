# Recomp 1.8 — travel, timezones and food coverage

**Unsigned iPhone source project. Native Xcode compilation, actual iPhone timezone changes, HealthKit exports, widgets and encrypted-file restore remain unverified.** See `Verification/BUILD_STATUS.md` for the checks actually run. No personal food, travel itinerary, measurements or Health data is seeded.

This update keeps the native instrument interface and existing features. No GPS permission, location service, flight lookup or new server is used.

## What changes when you land

New meals and local measurements save three separate facts: their absolute timestamp, the selected entry timezone, and their Gregorian local diary date. Viewing that record from another country no longer changes its diary date. The timestamp remains the chronological truth; the date label is for the diary.

For example, a dinner entered at 8 pm on September 17 in Seattle stays under **September 17** after arrival in Sydney. A September 18 meal in Sydney stays under **September 18** even after flying back to somewhere that is still on September 17. Existing recorded civil dates remain selectable; this does not permit logging a future event.

The app follows the phone's local Today. A deliberately selected historical date remains selected across a timezone change. Opening a historical food page chooses its known original timezone as the backfill default; **check the timezone and time when backfilling**, particularly on a mixed-zone date. A default is not an inferred itinerary.

### View or correct an entry

Open a meal or local measurement and use **Entry timezone**. A native searchable picker offers city/timezone identifiers such as `Australia/Sydney`, `America/Los_Angeles`, `America/Vancouver`, `America/Toronto`, `Europe/Paris` and `Europe/London`.

The ordinary date/time picker is displayed in that selected timezone. Changing just the timezone preserves the same instant and recalculates the local diary date; change the time as well only to correct when the event occurred. **Exact time · UTC** provides an unambiguous editor when a local hour repeats at the end of daylight saving. No meal or measurement is copied merely because the timezone changes.

Food rows show their original zone when different from the current device zone or when it needs review. Body history also shows the original time and zone. Charts use the saved civil dates; maintenance uses absolute timestamps separately.

## After a flight: review actual food coverage

Open **Today → Travel & food coverage**, or the same link in **Maintenance**.

1. Choose **Review a food / travel interval**. Set **Show times in** to a timezone you understand; changing that display zone does not change the interval's actual endpoints.
2. **Continue from last confirmation** starts exactly where existing coverage ended. Choose the end explicitly. **End at last device-local midnight** is useful after arrival: it closes the travel bridge at your new midnight, so ordinary day confirmations can resume from there.
3. Tap **Read food in these hours**. Review the actual elapsed hours, listed meals, totals, and optional additional Health food. Check that every food and drink in that time is included. Add or correct missing meals before confirming, then read the preview again.
4. Confirm. If existing confirmations overlap, explicitly review **Replace the listed confirmations** first. This removes those confirmations in full, not the foods. Any hours outside your replacement interval need another review.

Intervals include the start and exclude the end. A meal exactly at the boundary belongs to the following interval, never both. Intervals must have ended and be no longer than seven days; review longer spans in several segments. Ordinary daily confirmations remain available for routine days. Today's ordinary confirmation is not used until its original local day ends.

**This is not automatic flight detection.** The app cannot know what you ate during an unlogged flight, which timezone a historic timestamp originally used, or whether an empty Health result means denied access. Review gaps and overlaps rather than accepting an invented zero-food day. A repeated calendar date may contain two sets of meals; a skipped calendar date does not create a fasting day.

An ordinary day's status and a custom travel confirmation are separate. Use the coverage list to see custom intervals. **Mark incomplete** removes a confirmation without removing food. Editing or moving a meal invalidates every confirmation containing its old or new actual timestamp, even when editing from another country.

### Daily targets and widgets

Daily targets remain a **normal-day reference**, not an automatically prorated flight allowance. A long or repeated local date can contain more hours and more food. The app does not tell you to skip food because a flight date is already over target, or to eat extra to fill a short date.

The widget's local-only calories/protein use the same frozen diary membership as the app. It still excludes additional Health nutrition. Old-zone snapshots are rejected until refreshed. iOS controls actual refresh timing; this update does not establish instant widget refresh on landing or while locked.

## How maintenance now uses travel history

The current viewing timezone no longer filters out other timezone IDs. Seattle and Vancouver confirmations, for example, can remain contiguous when their actual boundaries meet. Different city names do not restart the baseline.

The engine uses the latest contiguous, ended, non-overlapping confirmed coverage in a **43-elapsed-day lookback**. It needs **at least 21 elapsed 24-hour days bracketed by comparable weigh-ins**. Gaps, exclusions, insufficient weights and stale or conflicting data can still prevent an estimate; a timezone change alone does not.

```
average logged calories per 24 hours = confirmed calories / elapsed 24-hour days
estimated maintenance = average logged calories - 7,700 × weight slope in kg per 24 hours
```

New confirmations retain timestamped food totals. If a boundary cuts through one, the engine sums the events actually inside it; it does not assume you ate uniformly each hour. Legacy confirmations lack that detail, so partial legacy boundary snapshots are not prorated. The analysis may trim to whole legacy intervals and need more supporting history. Third-party Health timestamps may themselves be approximate or daily aggregates; review their source rather than treating them as a verified eating time.

Weight comparisons remain **within the same scale/source**. For analysis, fixed UTC-date buckets provide one median value and timestamp per scale per bucket; slopes use the actual elapsed seconds between medians. This sampling rule is independent of the phone's timezone. It is not a claim that a UTC day is your biological day. At least three measured days per week in aggregate, no gap longer than about four days, and a scale spanning at least 21 elapsed days are still required. Other included scales need three measured days spanning at least seven elapsed days.

Body chart grouping is separate from that analysis rule. Stored readings are never offset-adjusted. Body-fat percentages and DEXA values still do not enter the maintenance equation. Travel conditions, hydration changes, sparse visits or disagreement between scales can withhold suggestions. Suggestions remain small, opt-in, cooldown-limited and review-before-apply.

The model is still an **unvalidated short-window energy-balance heuristic**, not a metabolic measurement. The sensitivity range is not a statistical confidence interval. No exercise calories are added again and no new target is applied merely because you crossed a border.

## Existing diary upgrade: unknown means unknown

Schema 1–6 diaries upgrade to **schema 7**. Old versions did not record capture timezones, so an accurate travel history cannot be reconstructed automatically.

Where exactly one old confirmation covers an entry, its zone is used as an **inferred** display choice. Otherwise, the device timezone at upgrade is the fallback. Both cases remain labelled **assumed; review**. This freezes the display once instead of regrouping it again at every launch. It does not claim that you were in that place. Correct the entry's timezone and confirm it explicitly when known.

The first successful load atomically persists that migration. Original timestamps, IDs, nutrients, measurements, scale tags, reports and Health receipts are retained. A failed persistence step does not overwrite the old diary or pretend the migration succeeded. Correctly stored legacy confirmed periods retain their original timezone and actual day bounds. Previously misdated or overlapping periods still need explicit review.

The new encrypted-backup payload retains clocks and confirmation intervals. Restore remains reviewed, empty-diary only, with preserved IDs and Health connections paused afterward. Native encryption execution and real-device migration still require Mac/iPhone testing. An old backup without capture zones has the same inference limitation as an old diary.

## Apple Health and other activity

New or edited ordinary food/body exports use the record's reviewed/recorded timezone, not the timezone where delayed syncing happens. An inferred legacy zone is **not** written as though it were known: check and confirm it first. Already acknowledged exports are not automatically replayed by migration; Health metadata is not retroactively repaired without reviewing/saving the entry through the normal update path.

Imported Health food/body samples use valid source timezone metadata when supplied. Without that metadata, their display remains current-zone-based and is not claimed to be capture-local. Exact-time food coverage review does not depend on guessing their original zone. Recomp's own exported duplicates remain excluded. DEXA sharing keeps its existing explicit clinic-timezone handling and stays separate from bathroom-scale analysis.

Strava/Strong workout summaries, steps and sleep remain **current-view-timezone context**, not a saved itinerary or original-night travel timeline. They do not change this maintenance calculation. No activity, body history, timezone log or DEXA report is added to food-estimator requests.

## Install and test

Keep the **same app bundle identifier, registered App Group and development team**. Export a verified backup and retain original reports first; install over the existing app, not by uninstalling. Once schema 7 is saved, older app versions cannot read it. Do not downgrade over your only copy.

No new permission or App Group is required. `Server/` is unchanged from v1.7.2; this travel update does not require redeploying it.

```bash
swift test
./scripts/check-travel.sh
./scripts/check.sh
# On your Mac with full Xcode and an iOS Simulator runtime:
./scripts/check.sh --require-native
```

The travel harness uses the actual diary coordinator and temporary files, with explicitly mocked Health reads/writes. Its timezone switches and seven relaunches are Linux process tests, not proof of iOS notification handling. The normal native gate creates a disposable simulator; it does not change your personal Health store.

Before using live records, test on a throwaway simulator: Seattle dinner → Sydney viewing; Sydney meal → a repeated US date; preserving a deliberately selected historical page; daylight-saving repeated hours; entry timezone corrections; adjacent flight coverage and an intentional overlap; correcting a food after confirmation; real permissions and delayed sync; widget/app consistency; migration/relaunch; and backup restore. Never put synthetic test meals or scans in your personal Apple Health.

## Implementation references

Primary Apple references reviewed September 18, 2026; these support API behavior, not verification of this app:

- https://developer.apple.com/documentation/foundation/timezone/autoupdatingcurrent
- https://developer.apple.com/documentation/foundation/calendar/autoupdatingcurrent
- https://developer.apple.com/documentation/healthkit/metadata-keys
