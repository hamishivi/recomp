# Recomp 1.6 — DEXA to Apple Health

**Source project, not a signed app. Native Xcode compilation, Apple Health permissions and real-iPhone syncing have not been verified here.** No actual scans or Health records from this conversation are embedded.

## Use it

1. Open **Body → DEXA scans**, import/enter and review your report as before.
2. Open the saved scan, then **Review Health sharing**. Select the compatible values you want to share. Each row shows the exact number, unit and definition; nothing is uploaded merely by importing a scan.
3. Check the scan date, time and clinic's timezone. Date-only reports default to a labelled approximate time (noon, or the current time if it is earlier today). Enter the actual time when known. The app does not claim the default time came from the report.
4. Confirm **I reviewed the selected values and time**, then **Save**. The app saves your choices and, if needed, requests the separate Health permissions. Grant the write permissions you choose.
5. Reopen the scan to see per-field status. **Write confirmed** records a successful write, not continuous verification that the sample still exists. Denied writes or errors remain pending. Use **DEXA scans → Sync reviewed scans now** to retry.

The connection is independent of the food/body switches. Connecting without approving any scans sends nothing. Granting weight access elsewhere does not opt scans in. Health permissions are system-wide per app/type; pausing a Recomp feature is separate from revoking those permissions.

## What can be shared

| Report input | Apple Health output | Conversion / limits |
|---|---|---|
| Explicit whole-body total mass | Weight | kg, lb or g converted to kg |
| Explicit whole-body body-fat percentage | Body Fat Percentage | 19% becomes `0.19` in HealthKit's percent unit; not 19 or 0.19% |
| Explicit whole-body fat-free mass | Lean Body Mass | kg; including bone mineral, not just soft tissue |
| Whole-body lean soft tissue **and** bone mineral content | Lean Body Mass | Sum of those two masses, explicitly labelled as calculated in the review |

Recomp retains the original report values and units. The derived Health summary does not replace report rows. An unqualified "lean mass" value is **not** treated as fat-free mass or muscle. Total mass plus fat percentage does not automatically create a lean value, because report percentage definitions can differ.

Eligible anatomical labels are explicit whole-body labels: `Total body`, `Whole body`, and their hyphenated forms. `Total` alone, subtotal, trunk, android, arms, and total-body-less-head are not assumed equivalent. Edit the report entry's region after checking its meaning.

Duplicate whole-body rows for the same metric block that field. A reported fat-free value conflicting with lean soft tissue + bone mineral by more than 0.2 kg blocks lean sharing; a lean result exceeding total mass by more than 0.1 kg is also blocked. These are rounding/consistency guardrails, **not validated clinical thresholds**. Check the source; the app does not silently correct it.

Fat mass, regional values, bone mineral density/content, T/Z-scores, visceral-fat metrics, and the report's RMR are not exported as standalone Health quantities in this implementation. RMR is not written as a day's burned energy. PDFs, clinic/scanner labels, comparison groups, source excerpts and notes are not exported. No height is inferred, so no BMI is invented. The full report stays in Recomp/your original Files location.

## Precisely what sync means

This is **Recomp → Apple Health export with updates and removals**, not automatic reconstruction of full DEXA reports from Health. Recomp is authoritative for its saved scan.

Selected compatible fields update when you review and save an edited scan. A new scan always needs its own sharing review. Stable identifiers are separate from the food and bathroom-scale namespaces; increasing versions allow replacement instead of repeatedly adding the same scan value.

Each metric has its own persisted receipt. An attempted-write marker is saved **before** calling HealthKit so a subsequent deletion can clean up after a crash even without a success receipt. API failures, permission denials and pending deletions survive restarts. Pausing stops new requests; a request already in flight may finish.

Removing a selected result from the report, making its definition no longer compatible, deselecting it, or deleting the scan queues removal of that scan's Recomp-owned sample. Queries restrict removal to the exact stable ID and Recomp's Health source, not another app's records. Previously selected fields that become valid again will resume sharing after the reviewed report is saved; use sharing choices to deselect them permanently.

**Remove this scan's Health exports** keeps the report in Recomp while removing its selected Health outputs. **Pause DEXA syncing** leaves existing Health data in place and postpones queued removals. Cleanup needs syncing enabled and write permission for that type. You can reconnect from the scan list even after deleting the scan. The pending counter includes both writes and removals.

Deleting a sample directly in Health does not delete the Recomp scan or invalidate its local receipt. Reopen **Review Health sharing** and save again to republish with a newer version. Another app's independent copy of the same scan is not automatically detected or removed; avoid exporting the same scan through both Recomp and your provider's app.

Sync runs while the app is active after changes, on foreground/open and on manual refresh. There is no background delivery. No API key, AI service or internet server is required for this integration.

## Keep scans separate from scale analysis

Recomp's scan exports carry an opaque scan ID, a DXA method marker, original calendar date, chosen timezone, approximate-time flag and value-definition code. The Health app may display **Recomp** as the source; do not assume it renders these custom fields as a special DEXA category.

Recomp recognizes its own marked exports and excludes them from bathroom-scale history and the maintenance fit, including after the local scan is deleted or the app is reinstalled using the same bundle identifier. This avoids a scan's measurement conditions or date-only timestamp changing the inferred calorie target. Daily Home/Girlfriend's measurements remain unchanged.

That separation is inside Recomp. Apple Health or other authorized apps may aggregate scan and scale measurements of the same type. Copies rewritten by another app may lose the identifying metadata; Recomp cannot reliably recognize every third-party scan. It does not calibrate either bathroom scale from DEXA.

## Update and data retention

Export first. Use the **same development team and bundle identifier** and install over the existing app; do not uninstall. Open the updated `Recomp.xcodeproj` and restore your signing details.

Schema 1–4 upgrades to **schema 5**, retaining scans, PDFs, diary, measurements, tags and existing sync receipts. Old scans remain unshared and the new connection is off until explicitly enabled. The scan schema itself is unchanged; separate Health links store selections, timestamps, attempted types and receipts. Tombstones retain the opaque ID and cleanup state after scan deletion, not its report values/PDF. Do not downgrade over the only copy; older versions reject schema 5.

An uninstall loses local reports, tags and pending cleanup. It does not guarantee deletion of existing Apple Health samples. CSV remains an export, not a full restore/import backup; the new sharing-state records are not included in the scan-values CSV. Native in-place upgrades remain untested.

## Testing

Run `swift test`, `./scripts/check-store.sh`, and `python3 scripts/check-dxa-health.py`. On your Mac, also run `./scripts/check.sh` for the actual simulator build. See `Verification/BUILD_STATUS.md` for what was run here and the real-device checklist.

Never save synthetic scan fixtures into your personal Apple Health. Exercise permission and deletion tests in a separate simulator/test environment before using real data.

## Primary references

Reviewed September 18, 2026. These document supported APIs and terminology; they do not validate this implementation:

- Apple HealthKit data types: https://developer.apple.com/documentation/healthkit/data-types
- Apple lean-body-mass quantity: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/leanbodymass
- Apple body-fat percentage quantity: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodyfatpercentage
- Apple metadata/sync keys: https://developer.apple.com/documentation/healthkit/metadata-keys
- Apple sync identity: https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier
- Apple permission handling: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- FitTrace's own published DEXA/Health mapping identifies Health lean body mass as fat-free mass: https://apps.apple.com/us/app/fittrace-sync/id1531995820
