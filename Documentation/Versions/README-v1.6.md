# Recomp 1.6

**New in 1.6: reviewed DEXA → Apple Health sharing.** Open a saved scan → **Review Health sharing**. Choose whole-body weight, body fat and compatible lean body mass. Review the value definitions and scan time, then grant the permissions you choose. Edits replace selected fields; removals have a persistent, per-field cleanup queue. Scan exports stay outside Recomp's bathroom-scale maintenance model. No PDF, notes or regional/bone/RMR values are sent to Health. See [DEXA-HEALTH.md](DEXA-HEALTH.md). Schema 1–4 upgrades to 5 without automatically sharing old scans.

**From 1.5: DEXA / DXA report ingestion.** Import a PDF, paste text or enter results, review the metric/site/units, and keep an optional protected PDF copy. Clear labelled text becomes unselected review candidates; complex tables and image-only scans require manual entry. See [DEXA.md](DEXA.md).

**From 1.4: Instrument-style native interface.** Off-white/graphite/orange, aligned monospaced readouts, restrained charts, native forms and System/Light/Dark appearance. Open **Settings → Interface preview** to inspect sample screens without writing data. See [DESIGN.md](DESIGN.md). The HTML/PNG design references are illustrations, not native iPhone screenshots.

**From 1.3: Scale/location tags and scale-aware maintenance.** See [SCALES-LOCATIONS.md](SCALES-LOCATIONS.md) for Home/Girlfriend’s tags, custom labels, old/imported reading tags, separate chart curves and within-scale comparisons. These features stay local and require no GPS or server.

**From 1.2: Body measurements and trend-based maintenance.** See [BODY-MAINTENANCE.md](BODY-MAINTENANCE.md) for measurement logging, separate Health permissions, complete-day reviews, conservative target suggestions and read-only examples. These features need no AI server. Native Xcode/device verification is still outstanding.

An iPhone macro diary with a native SwiftUI interface and an opt-in Apple Health integration. iOS 17 or later. No third-party iOS packages, ads or analytics. Manual entry and Apple Health work locally; optional photo/text estimation uses the included authenticated AI server.

**This is an unsigned source project, not an installable App Store or TestFlight app.** The core tests were run here, but the native iOS build and real HealthKit permissions have not been tested. See `Verification/BUILD_STATUS.md`.

## Photo and text estimates

Take or choose up to **three photos**, or describe your meal without a photo. Receive an
editable ingredient breakdown, estimated calories/protein/carbs/fat, assumptions and useful
questions. Refine the current estimate with details such as “I ate half the rice” or
“the latte used skim milk.” Manually edit or scale each item, remove foods, add missing
foods, and protect corrected values from later AI changes. Undo is available for the last
20 breakdown/refinement actions in the current session.

**This feature requires setup.** A dependency-free Node server is included in `Server/`.
It needs your own OpenAI API key and an HTTPS address reachable by your iPhone. There is
no hosted server or API credit in this download. API usage is separately billed from
ChatGPT. Manual logging remains available without it.

**[Photo/text setup and usage →](PHOTO-SETUP.md)**

Only **Log meal / Save changes** commits the reviewed total to the diary and queues its
four nutrients for Health when enabled. Refinements before confirmation do not log meals.
Existing AI meals reopen from **Edit food → Refine food breakdown** and keep the same
meal identity for Health replacement. Original images are not saved or exported.

## Start on your Mac

1. Unzip this folder and open **Recomp.xcodeproj** in Xcode. Use an Xcode version that supports your iPhone's installed iOS version; the app's minimum deployment target is iOS 17.
2. Select the **Recomp** app target, then **Signing & Capabilities**. Choose your development team, leave automatic signing on, and replace `com.example.recomp` with an identifier unique to you, such as `com.yourname.recomp`. The HealthKit capability, entitlement and privacy purpose strings are already included.
3. Choose your iPhone as the run destination and press **Run**. Pair/trust the device and enable Developer Mode when Xcode asks. A physical-device build requires a signing profile that supports HealthKit. Capability availability depends on Apple program membership; a simulator build can be used to check the interface without device provisioning.
4. The diary starts empty with your targets and saved-food shortcuts. In **Settings → Connect Apple Health**, review the explanation and grant the read/write permissions you choose. Connecting also queues any existing local meals for export.

No data from your ChatGPT Health connection is embedded in this project or transferred automatically. The app requests its own on-device Health permissions. Apple setup references are linked below.

## What is implemented

- **DEXA → Apple Health:** opt-in per-scan selection of compatible whole-body summary values, update/delete syncing, independent permissions, per-type receipts and separation from scale analysis. See `DEXA-HEALTH.md`.
- **DEXA scans:** editable report values, original units/sites, optional retained PDFs, comparison groups, scan-only history and CSV export. Source reports are never automatically treated as bathroom-scale readings.
- **Interface:** native tabs, navigation, sheets, Forms, system controls and Charts; a new quiet palette and original icon. Appearance follows the system by default, with manual light/dark options.
- **Today:** calories and macros eaten, daily targets, remaining/over values, date navigation and a food diary grouped by meal.
- **Food entry:** add/edit/delete, time and date, decimal values, portion scaling, estimate flag, notes and reusable saved foods. Local logging does not require Health access.
- **Starting targets:** 2,500 kcal / 170 g protein / 285 g carbs / 75 g fat. These are editable trial targets from our conversation, not a measured maintenance requirement. Macros imply 2,495 kcal; the 5-kcal rounding difference is intentional.
- **Your usuals:** estimated shortcuts for a 12 oz whole-milk latte, one scoop of protein powder with water, Little Thai chicken combo, two fried eggs and the inferred Core Power Elite 42 g shake. You review a shortcut before saving it. Brand, flavour, serving size and restaurant values were not fully verified; every starter shortcut is marked as an estimate. Nothing is automatically logged.
- **Apple Health export:** dietary energy, protein, carbohydrates and total fat for meals you log. Edits use stable per-meal/per-nutrient identifiers and increasing versions; failed or partially permitted writes remain pending. Deletions are stored as a persistent cleanup queue.
- **Apple Health read:** readable nutrition for the selected day can be added to the dashboard. Weight can be logged locally and optionally written from the Body tab; the Trends tab shows daily medians and seven-calendar-day rolling averages separately for each scale.
- **Privacy:** a protected local JSON diary, no telemetry, and explicit CSV export of local meals. AI estimation is optional, asks before each upload, and sends only the selected meal photos, typed details and that meal’s current breakdown—not Health records, weight, targets or other diary entries. See `PHOTO-SETUP.md` for retention caveats.

For orientation, the five starter foods sum to about **1,780 kcal, 127 g protein, 167 g carbs and 64 g fat**, not exactly the rounded 1,800/125/170/65 earlier conversation estimate. These are shortcuts, not verified intake records.

## Precisely what “sync” means

Sync runs after food or measurement changes, on foreground/open, and when manually refreshed. **No background delivery is implemented.** Keep the app open to finish pending exports and cleanup.

The local Recomp diary is authoritative for meals entered here. Health samples carrying both this app's source and a known local meal ID are excluded from imported totals, including samples associated with pending deletions. This prevents Recomp's own exports from being counted twice. Nutrition from other sources is additive and can be disabled in Settings. There is no reliable automatic deduplication of a meal independently logged in multiple other apps.

Each nutrient has a separate export receipt. Permission for protein alone does not falsely mark the entire meal as exported. A completed authorization prompt does not mean permissions were granted. Apple does not reveal read denials; empty reads are not proof of access or proof of zero intake. Limited history access may also restrict results.

If a previously positive value becomes zero, the app removes its previous sample for that nutrient. A retry after a crash reuses the same sync identifier/version. Deletion queries restrict both the stable identifier and the app's own HealthKit source; they do not intentionally remove another app's data.

Deleting an exported sample directly inside Health does **not** delete the local Recomp meal. “Exported” records the last successful write, not a continuous guarantee that a sample still exists. Make edits/deletions in Recomp to keep its diary and exports aligned. Old readable exports with no corresponding local record, for example after reinstall, may appear as additional Health nutrition.

Pausing integration does not revoke system permissions or erase prior Health exports. A request already in flight may finish. Manage permissions separately in Apple Health. Apple Health's system cloud-sync behaviour is controlled by your device settings, not this app.

## Data and limitations

The local diary is stored in the app's Application Support/Recomp/diary.json. iOS writes are atomic and use complete file protection. The directory is excluded from device backups. **Uninstalling loses local meals, measurements, scale tags, targets, saved foods, DXA scans/PDFs and analysis history.** Export first. CSV export does not include imported Health samples or provide a restore/import feature in this version.

The Trends calorie chart is explicitly **local diary only**, includes partially logged days, and never interprets an unlogged day as zero food intake. Changing targets changes the reference target for all displayed dates; historical target changes are now retained in the Maintenance tab; the existing Trends calorie chart still shows the current reference target. Weight charts use separate per-scale daily medians (local measurements take priority over imports within each scale/day) and measured days in the preceding seven-day window, without filling gaps.

Not implemented: barcode or food-database lookup, on-device/offline AI inference, unreviewed automatic calorie changes, body-fat prediction, workout logging, multi-device diary sync, background Health delivery, restore from CSV, App Store distribution, or a web app. The optional AI server requires an API key; the local diary and Health integration do not.

## Verify and develop

Run core tests on a Swift 5.9+ toolchain:

```sh
cd Recomp
swift test
```

Run core, coordinator, interface and server checks, then an unsigned simulator build on a Mac with Xcode:

```sh
./scripts/check.sh
```

The app project has no test target; the standalone Swift package tests core models, arithmetic, merging, persistence and estimation rules. `cd Server && node --test` runs the proxy unit/HTTP tests with a mocked AI provider; those tests do not spend API credit or establish live AI accuracy. A macOS GitHub Actions workflow is supplied but has **not** been run for this delivery. It only runs when you put the project in a repository and trigger it yourself.

The Xcode project is already generated. After adding/removing Swift source files, regenerate it with `python3 scripts/make_project.py`, or add files in Xcode. Regeneration resets the generated project settings and Info.plist; reapply your team and bundle ID afterward. No XcodeGen, CocoaPods or npm install is required.

### Layout

```text
Recomp.xcodeproj/       Native iPhone project and shared scheme
Recomp/Core/           Models, arithmetic, merge rules, CSV, local state file
Recomp/Services/       HealthKit, diary coordinator, local PDF reader, estimation client and Keychain
Recomp/Views/          Today, food/AI editors, Body, Maintenance, trends and settings
Recomp/Assets.xcassets Original icon and adaptive light/dark/contrast palettes
Examples/             Synthetic DXA PDF/text; not loaded into the app
Design/                Editable icon SVG and labelled, non-functional visual reference
Server/               Authenticated single-user OpenAI proxy, Dockerfile and HTTP tests
Tests/                Portable core unit tests
TestSupport/          Clearly labelled mocked coordinator harness
Verification/         Actual verification status and device checklist
scripts/              Check script and optional project regeneration
```

## Apple references

Reviewed September 17, 2026:

- [HealthKit nutrition types](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers)
- [Authorizing Health access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Sync identifiers and replacement versions](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)
- [Write authorization status](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:))
- [Protecting health data](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
- [Running on simulated and physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Capability availability](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

The reference links describe Apple APIs. They are not evidence that this particular app has passed device testing or App Review.


## AI implementation references

Retained from the 1.1 photo-estimation update (unchanged API implementation; not newly reverified for 1.4):

- [OpenAI image input](https://developers.openai.com/api/docs/guides/images-vision)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini)
- [API key safety](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety)
- [API data controls](https://developers.openai.com/api/docs/guides/your-data)
- [Separate ChatGPT/API billing](https://help.openai.com/en/articles/9039756)
- [Apple Photos picker](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)
- [Camera purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription)
- [Privacy manifest data declarations](https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest)

These document the APIs, not proof of this app’s native build, model accuracy, App Review
compliance or real-device HealthKit behaviour. See the verification report.
