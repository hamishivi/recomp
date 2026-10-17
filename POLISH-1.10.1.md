# Recomp 1.10.1 — fixes and interface refinement

## Update your existing project

The in-place patch accepts the supplied **v1.10** source. It preserves your bundle identifier, development team, App Group and schemes. Unexpected edits to a replaced source file stop the update; they are not overwritten.

Close Xcode. Unzip `Recomp-v1.10.1-Patch.zip` in Downloads, then run:

```bash
python3 ~/Downloads/Recomp-v1.10.1-Patch/apply.py \
  "$HOME/Downloads/Recomp 5" --apply
```

That destination comes from your earlier Xcode message. Use the actual folder containing `Recomp.xcodeproj` if you moved it. Omit `--apply` for a dry run. Source rollback copies go into `.recomp-update-backups`; these are **not diary backups**. Keep an encrypted diary backup and original reports separately.

Reopen the **same project** and Run. Do not uninstall. The full source ZIP is available for a fresh setup; reapply your existing signing identifiers when using it for an update. `setup.md` contains the first-install steps.

Version **1.10.1 / build 15 / schema 7**. No migration, permission, server deployment, new API key or App Group registration is required by this update. Health, travel, maintenance calculations, backup cryptography and the network API contracts are unchanged.

## What looks different

The home summary uses the existing four concentric rings and exact numerical values in a more compact layout. Rings and numbers sit side by side when they fit, with a stacked arrangement on small screens and at accessibility text sizes. Over-target values remain explicit; tiny balances no longer say “0 over”. Estimated totals carry the approximate marker.

The date stays at the top; there is no app-name heading. Log and Check share one action row where space permits. Food rows no longer repeat successful local-save/Health-export labels; pending exports remain visible. Borders and whitespace still separate sections, not numbered badges.

The food form uses a strip of photo thumbnails. Tap a photo to edit its role/note or remove it. Sources remain available by opening a food in Breakdown. Less-used logging settings—notes, saved-food creation, retained photos and deletion—are under **More options**. The selected date and timezone remain visible. UTC details are expandable; the legacy assumed-timezone warning remains visible.

Settings is grouped into Food, Connections, Preferences and Data. **Apple Health** is a submenu rather than a long block on the Settings page. **Your usuals** remains its own submenu and is also available inside food entry. CSVs are generated only when the chosen export is tapped, not on every Settings render.

All interaction still uses native SwiftUI navigation, forms, sheets, menus, photo selection and controls. The interface has not been rendered or performance-profiled on an Apple device in this environment.

## Food-editing fixes

- **Undo is a toolbar button**, including after removing the last ingredient. It restores nutrition, the food name, estimation context, protection state and the previous verified/estimated status. Manual typing is grouped until the field loses focus. Up to 20 food-edit checkpoints are retained in the open draft.
- Undo restores the last valid numeric values—not invalid raw input text. It does not undo the meal time, photos, notes or logging options. Cancelling the form still discards the whole unsaved draft after confirmation.
- Equal-total replacements (for example, a saved food with the same calories) refresh the input fields correctly. Manual totals too large for the AI schema remain loggable and undoable without an AI request.
- **Half/Double preserves the ingredients**, their identities and proportional values. Scaled portions are protected against a later AI rewrite; an explicit unlock remains possible. A single Undo restores the previous portion.
- Opening an unchanged ingredient no longer automatically locks it. Manual edits default to protected unless explicitly unlocked. The ingredient editor asks before discarding changes.
- Removing/replacing photos clears obsolete numbered photo references immediately. Nutrition Undo cannot assign old sources to replacement images. An AI response for superseded photos is rejected rather than overwriting the current draft.
- Photo imports use a cancellable batch identity. A superseded/cancelled batch cannot append images or clear a newer loading indicator. Photos commit together once the batch is prepared. The token state machine is tested; native picker/camera execution remains unverified.
- Duplicate photo IDs, invalid timezones/times and overlong context are rejected before save/request. Text is not silently truncated into a different AI context.
- The unchanged-existing-meal Save path closes without issuing a diary update, avoiding needless completion invalidation or Health re-export. This view-level routing needs the supplied native UI check on your Mac; the Health adapter is not modified.

Image decoding for the thumbnail strip is retained across unrelated form edits. This removes a repeated work path; it is **not a measured iPhone speedup**. Photo preparation, large diaries and Settings export performance still need device profiling.

## Quick checks

```bash
./scripts/check.sh
# Focused executable model/controller regressions:
./scripts/check-polish.sh
# Native build and UI tests, on your Mac with Xcode:
./scripts/check-native.sh
```

Use a disposable simulator for synthetic food/Health fixtures. Try typing a value, selecting a usual, Undo, Half/Double, removing the last food and Undo, replacing photos, cancellation, invalid fields, Check without logging, the Apple Health submenu, large text and dark mode. Native tests are supplied, not claimed to have run here.

**Verification/BUILD_STATUS.md** separates actual portable tests, static source checks and unverified native behavior. Estimates and maintenance recommendations remain unvalidated fitness heuristics—not medical measurements.
