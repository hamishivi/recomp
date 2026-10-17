> **v1.9 setup update:** use [setup.md](setup.md). AI can now call OpenAI directly with a personal key; references below to a required server apply only to the optional server route. Other feature semantics are retained.

# Recomp 1.7 — backups, photo evidence, food checks, activity and widgets

**Unsigned iPhone source project. Native Xcode compilation, widget rendering, exact Apple cryptography execution, in-place upgrades and real HealthKit behaviour have not been verified in this environment.** Read `Verification/BUILD_STATUS.md` and run the Mac checks before relying on this version for personal records.

The original instrument-style interface, native SwiftUI controls, scale-aware maintenance, body measurements, DEXA review/Health exports and food logging are retained. This update does not change the maintenance equation or automatically add workout calories to your food target.

## 1. Encrypted backup and restore

Open **Settings → Tools → Encrypted backup & restore**. Choose a password of at least 12 characters, repeat it, and select where to save the `.recompbackup` file in the native Files exporter. Keep the password separately in a password manager. There is no password recovery. Backups are manual snapshots, not automatic iCloud or multi-device sync.

The encrypted payload includes local meals and retained meal photos, food breakdowns, targets and saved foods, body measurements, scale tags, imported-reading annotations, context notes, DEXA entries and any retained PDFs, complete-day snapshots, target/maintenance history, appearance and Health sync identities/receipts/cleanup queues. It includes any Health nutrition totals that you explicitly confirmed in food-day snapshots. It does **not** contain your API key, estimator-server token/configuration, or raw imported Health workout/step/sleep caches. Configure the estimator separately after reinstalling.

**Restore is intentionally empty-diary only.** Choose a backup, enter its password, review its creation date and record counts, and explicitly confirm. Existing logs are never overwritten or merged. Custom targets, saved foods or scale/history settings may also make the destination nonempty. Use the same app bundle identifier and development team. Do not uninstall a working installation until you have verified an exported backup using the Mac test workflow and retained your original reports separately.

Restore preserves original IDs, versions, receipts and deletion queues; it does not call the food-logging path or create fresh record IDs. All Health integrations, activity reads and widget numbers are switched **off** after restore. Review the recovered diary before reconnecting. Reconnection does not blindly resend versions already acknowledged as exported.

A receipt is not proof that a sample still exists in Health. An older backup cannot reconcile newer changes made elsewhere, recover later records, or identify every third-party copy. Health remains a separate store: restoring does not erase it. Review discrepancies explicitly; do not assume that restoring an old file also rolls Health back in time.

### Cryptography and limits

The native implementation uses CryptoKit AES-256-GCM, a random nonce, a fresh 16-byte salt and CommonCrypto PBKDF2-HMAC-SHA256 with 600,000 iterations to derive a 32-byte key. The version/cipher/KDF/salt header is authenticated. Version and size checks happen before password derivation. The file does not expose diary counts or dates outside the encrypted payload. This is not a security audit or a claim that a weak password is safe.

The payload is limited to 160 MiB and the encoded encrypted file to 230 MiB. The existing report budget is 48 MiB and retained meal photos have a separate 48 MiB global budget. Large attachments increase memory and disk-write costs; practical iPhone limits may be lower. No full decrypted backup is deliberately written to a temporary file. Import/export, cryptography and large-backup performance still require native testing.

Run `./scripts/check-backup-mac.sh` on macOS to test the **exact** native encryption implementation against an independent synthetic fixture, wrong passwords and tampering. Linux core tests cover payload/restore rules, not execution of CryptoKit. Keep your original DEXA PDFs independently even when backed up here.

## 2. Multiple photos as evidence for one meal

Open **Today → Estimate** or **Today → Check food · without logging**. Take photos or select up to **six** images in the native photo picker. For each image, optionally choose a role and add a short note:

- Food/plate, nutrition label or packaging.
- Menu/receipt or leftovers.
- Auto when unsure.

One plate, its package and its label are **evidence for the same food**, not automatically three foods. Use the description to distinguish genuinely separate items. A leftovers photo needs context about what was served and eaten.

The server asks the image model to prioritize legible label values, state per-serving/per-100 g bases and serving multipliers, and distinguish label extraction from visual inference or assumptions. Item-level **Evidence used** is editable-context provenance, not independent verification. A blurry label, hidden oil, ambiguous portion or a barcode alone is not sufficient for a reliable number. There is **no barcode database lookup** or guarantee that every label/table is extracted correctly.

Review and edit the food items, portions and macros. Manual edits remain protected from AI changes by default; unlock an item to re-estimate it. Refine with more text or changed photo evidence. Nothing enters the diary until **Log meal** / **Save changes**.

**Keep photos attached to this meal** is on by default when saving a meal with images and can be disabled. The app keeps re-rendered JPEGs (longest edge at most 1600 pixels, at most 1.5 MB each) without original photo metadata. Retained photos reopen with the food breakdown and are included in encrypted backups. They are not exported to Apple Health. Removing a meal/attachment does not delete the original from your Photos library. “Your usuals” remains an aggregate shortcut, not a photo collection. Unsaved scratchpads are discarded on close/termination.

Each AI estimate/refinement still requires your optional server and separately billed API access. Selected images are resent only after the existing per-request confirmation. Daily totals, activity, body history, targets and DEXA reports are not sent to the food estimator. Manually typed personal information will be part of your request.

**Update the server too.** Deploy the `Server/` folder in this release. The request limit is now 12.3 MB for up to six images; any HTTPS proxy must allow at least that JSON size and an upstream timeout over 70 seconds. Older three-image servers cannot handle six-image requests. Existing environment-variable names and single-user access tokens remain unchanged. Provider requests still use `store: false`; this is not a zero-retention promise.

## 3. Check without logging

**Today → Check food · without logging** opens a disposable scratchpad. Describe food, attach evidence or choose **Enter known values manually**. You can edit/refine a breakdown and inspect its calories/macros. A hypothetical comparison shows the selected day's current totals, totals with that food added, and remaining/over-target values.

This is a food/nutrition checking tool, not a general medical chatbot. It has **no Save/Log button in Check mode**. It does not mark days complete, change targets, create a meal, queue Health samples or persist a planned meal. **Use as a food entry…** explicitly switches to logging controls; you must still confirm **Log meal**. Closing the check discards it. Repeated checks do not accumulate in the diary. Entering known values manually requires no server.

## 4. Strava, Strong, steps, sleep and context

Open **Settings → Tools → Activity & context / Strava · Strong**, or the **Routine context** link in Maintenance.

The integration is **Strava / Strong → Apple Health → Recomp**. It is not direct Strava/Strong account access or a new workout recorder.

### Enable sharing

1. In **Strava**, open Settings → Manage Apps and Devices → Health, connect, and turn on **Send to Health**. Allow the workout data you want shared.
2. In **Strong**, open Profile → Settings → App Integrations → Apple Health → Connect. Enable workout sharing.
3. In **Recomp**, request **read** access for workouts, steps and sleep in Activity & context. Recomp never writes or deletes workouts.

Official setup references: [Strava](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava), updated August 17, 2026; [Strong](https://help.strongapp.io/article/147-sync-with-apple-health), currently published help page dated February 21, 2022. Menu names may change; check the source apps' current screens. These references establish the integration route, not that this Recomp build has passed native testing.

### What Recomp displays

Up to 30 days of available workout summaries: type, start, reported duration, distance when supplied and source app. **Strong individual exercises, sets, repetitions and lifted weights are not imported in this version.** Routes, heart-rate streams and detailed running splits are not read. Keep detailed workout analysis in the recording apps. No separate OAuth credentials or app-specific subscriptions are added by Recomp.

Steps use HealthKit's merged daily statistics, not a naive sum of phone and Watch samples. Sleep merges overlapping asleep stages within **one** source and excludes awake/in-bed intervals. When multiple sleep writers exist, choose one; Recomp does not sum trackers' totals. A sleep night is the noon-to-noon interval ending on the displayed date. Missing records stay missing. Today's data and coverage can be incomplete; empty results are not proof of zero activity or granted permission.

Likely duplicate workouts from different writers are **flagged**, not silently removed. Select a workout source or hide a particular copy locally, with an undo/restore option. The filter is a viewing preference and does not delete Health data. Exact duplicate sample IDs are deduplicated. Recreated samples have new IDs, so an old hiding choice may not follow a replacement.

Reads run when the app opens/foregrounds and on refresh, not continuously in the background. Pausing clears the in-memory activity view, but does not revoke system Health permissions. Raw activity stays in memory and is not included in exported local backups or sent to the food AI server.

Add dated **travel, illness, creatine change, weighing conditions, training/routine change or other notes**. These are annotations, not diagnoses or automatic exclusions. Maintenance shows recent notes and, with sufficient step-day coverage, a descriptive comparison of the past two weeks. **Neither workouts nor steps/sleep add an “eat back” allowance, change the maintenance equation or automatically alter macros.** This release does not infer muscle gain, readiness or causality from those signals.

## 5. Native Home Screen widget

In **Settings → Tools → Home Screen widget**, optionally enable calories/protein numbers. They are **hidden by default**. The widget uses **today's local food entries only** and is labelled LOCAL DIARY. It can differ from the Today screen when additional Apple Health nutrition is included. It shares no meal names, weights, scale tags, photos, DEXA reports, API secrets or raw Health data with the extension.

The small widget opens Today. The medium widget includes native **Log**, **Check** and **Weigh** links that open the corresponding editor without saving. The palette follows the system appearance. No simulated hardware controls or replacement system navigation have been added.

Refreshes are requested on local changes and foreground use; iOS controls delivery. The snapshot has a date/time-zone check and a scheduled midnight entry that hides the previous day's numbers, rather than pretending they are current. Refreshing is not guaranteed instant. Privacy-sensitive text and complete Data Protection are configured; actual lock-screen/redaction behaviour still needs iPhone verification.

### Xcode App Group setup (new in 1.7)

The app and widget need the **same registered App Group**, enabled in Signing & Capabilities for **both Recomp and RecompWidget**. The widget identifier must be a child of your existing app identifier. Keep your current app ID/team for an in-place update.

The supplied defaults are `com.example.recomp`, `com.example.recomp.widget` and `group.com.example.recomp`. Replace them with identifiers you own. To regenerate all matching settings together, run from the unzipped Recomp folder:

```bash
python3 scripts/make_project.py \
  --bundle-id com.yourname.recomp \
  --app-group group.com.yourname.recomp \
  --team YOUR_TEAM_ID
```

Use the **existing** bundle ID rather than inventing a new one for an installed diary. Register/select that group in Xcode for both targets; the generator does not create Apple developer-account resources or provisioning profiles. Capability availability depends on your signing account. Both Info files and entitlements use `RECOMP_APP_GROUP`, set by the generator. Without a usable group, the main diary still works but the widget cannot load a snapshot.

Open `Recomp.xcodeproj`, select the **Recomp** scheme and an iPhone simulator or paired device, and Run. The scheme embeds/builds the new **RecompWidget** target as a dependency. On iPhone, touch and hold the Home Screen, choose Edit → Add Widget and search for Recomp.

## Update and verify

Schema 1–5 diaries migrate to **schema 6**, retaining old records and queues. Existing meals without photos remain valid. Activity reads and widget numbers start off. Updating does not automatically upload photos, reconnect a paused integration or log any samples from this chat. Old versions reject schema 6: do not downgrade over your only copy.

Native installation/upgrades remain unverified. Before replacing an installed version, retain its CSV exports/original reports. Keep the same bundle identifier and development team, and install over it rather than uninstalling. The new backup cannot retroactively recover a diary already lost before this version.

```bash
swift test
./scripts/check-store.sh
./scripts/check-estimator.sh
python3 scripts/check-features.py
(cd Server && node --test)
# macOS only — exact backup cryptography and unsigned app + widget build:
./scripts/check-backup-mac.sh
./scripts/check.sh
```

Native acceptance priorities: build both targets; six-photo label/plate/leftovers selection and retention; manual and AI checks leave the diary unchanged; backup/wrong-password/restore of a throwaway diary; partial Health permissions; real Strava/Strong sessions and duplicate writers; sleep across DST; widget privacy, midnight rollover and deep links; same-ID in-place upgrade. **Never put synthetic test workouts, meals or scan fixtures into your personal Apple Health.**

## API / implementation references

Reviewed September 18, 2026. These support the APIs and terminology, not validation of this app:

- [OpenAI image inputs and multiple images](https://developers.openai.com/api/docs/guides/images-vision)
- [Apple WidgetKit extension, privacy and Data Protection](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [WidgetKit sharing strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- [HealthKit statistics](https://developer.apple.com/documentation/healthkit/hkstatistics)
- [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [OWASP PBKDF2 password work factors](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
