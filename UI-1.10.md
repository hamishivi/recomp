# Recomp 1.10 — food entry and home interface

## Update your existing Xcode project

Use **Recomp-v1.10-Patch.zip** to keep your signing setup. It accepts the supplied 1.9 or 1.9.1 source, includes the startup fixes, and stops on unexpected edits.

Close Xcode, unzip the patch into Downloads, then run:

```bash
python3 ~/Downloads/Recomp-v1.10-Patch/apply.py "$HOME/Downloads/Recomp 5" --apply
```

That destination is the project folder from your previous compiler message. It must contain `Recomp.xcodeproj`; adjust the path if you moved it. Omit `--apply` for a dry run. The updater checks all payload/source hashes before writing, backs up replaced source files under `.recomp-update-backups`, preserves signing identifiers and schemes, and makes atomic per-file replacements. This is a source backup, not a diary backup or a full filesystem transaction.

Reopen the **same** Xcode project and press Run. Do not uninstall the app. The full archive is also available as `Recomp-Unified-Food-v1.10.zip`; restore your existing bundle ID, App Group and team if using it instead. A first install is covered in **setup.md**.

## Home

The navigation bar shows the diary date, not an app-name heading. Four solid concentric rings show calories, protein, carbs and fat, outside in. Exact consumed/target values and remaining/over amounts are underneath. Rings stop at a full circle; they do not wrap excess intake into another goal or hide the true total. A zero/missing target shows an empty track and “No target”.

Panels use thin borders, spacing and sentence-case headings instead of numbered badges. The muted instrument palette and native navigation, date picker, forms, menus, sheets, photo picker and Charts remain. Ring colors adapt to light/dark appearance, with labelled numerical rows so color is not the only cue. Reduce Motion disables ring interpolation; larger text uses stacked rows.

## One food form

**Log food** opens one form for a name, saved food, photos, text details and typed nutrition. Up to six food/label photos can be attached even without using AI.

**Your usuals** is inside that form. Selecting a saved food fills the draft; it does not create a diary entry or write to Health. Replacing nonzero food prompts first and preserves the current time, meal, notes and attached images. The form remains editable.

**Estimate nutrition** optionally sends approved food details/photos using the existing direct or server connection. Its response fills the same form. **Update estimate** accepts further details. No automatic request is made when adding a photo or selecting a usual. AI charges and upload confirmation are unchanged.

The nutrition numbers remain directly editable. Editing aggregate totals replaces stale ingredients with one protected total. Open **Foods** to edit individual foods, add/remove items, view sources or unlock a total before re-estimating it. Manual values can be saved without an API key. Invalid field input blocks both save and estimation instead of reusing a previous valid number. Review the **Estimated** switch when you have verified label/serving values.

**Save** is the only logging action. Edits keep the existing meal ID and use the normal Health-update and day-confirmation-invalidation paths. Cancel asks before discarding a changed draft. Photos can be kept or dropped independently of the meal; dropping the local copy does not delete the original in Photos.

**Check food** uses the same form without a Save action. **Log this food…** changes to logging controls; Save is still required. Checking does not alter diary totals, confirmations or Health.

## Settings and shorter copy

**Settings → Your usuals** is a searchable submenu. Swipe to remove a shortcut without removing logged meals. Privacy details are in their own submenu, and longer explanations have been shortened on the home, food, day-confirmation, goals and settings screens. Consent, API-charge, data-loss, timezone and incomplete-data warnings remain available.

Settings paths renamed in this update: **Backup & restore** and **Activity & notes**. Their behavior is unchanged. The setup guide includes the current labels.

## What did not change

Diary schema stays **7**. This release does not add a migration, permission, Health type, App Group or network endpoint. Scale-aware travel/maintenance calculations, DEXA mapping, backup encryption, workout import and API/proxy protocols are unchanged. Steps and workouts remain context, not a new calorie adjustment model. No server redeployment or API-key setup is needed.

## Test on your Mac

```bash
# Project root, after applying the patch:
./scripts/check-native.sh
```

The native runner uses a disposable simulator and does not write synthetic records to personal Health. Added UI cases check the single entry path, photo controls on new/edited food, usual selection without logging, the Settings submenu and cancel confirmation. They are supplied but **not executed in this Linux environment**.

Then open **Settings → Interface preview** for the actual SwiftUI components with read-only sample data. Check light/dark, large text, Reduce Motion, zero and over-target totals. Test a genuine manual meal and photo entry on your phone after the native gate succeeds. Retain a verified backup/original reports first.

See **Verification/BUILD_STATUS.md** for actual portable results. No native rendering, UI performance, camera, HealthKit or real-device upgrade is claimed to have been tested here.

### Apple API references

- https://developer.apple.com/documentation/swiftui/shape
- https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)

These document APIs, not verification of this build.
