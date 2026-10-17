> Version 1.5 adds a separate DXA log and upgrades diary schema to 4. See [DEXA.md](DEXA.md) and the current verification report. The release-specific details below describe earlier versions.

# Recomp 1.4 — Instrument interface

An original, Teenage Engineering–inspired visual direction: off-white panels, graphite ink, small orange accents and precise readouts. No Teenage Engineering logos, typefaces, product graphics or affiliation are included.

**This is the updated native SwiftUI source project, not a signed app.** The design-reference images are separately rendered illustrations, not screenshots from an iPhone or simulator. Native Xcode compilation and device rendering remain unverified.

## Try the interface

Open `Recomp.xcodeproj` on a Mac with Xcode, select an iPhone simulator and Run. No AI server is needed to inspect the interface or use the local diary, measurements and maintenance analysis.

In **Settings → Interface**, choose **System, Light or Dark**. System is the default. Under **Interface preview**, switch between Food, Body and Maintenance to inspect the real SwiftUI components with labelled synthetic data. The gallery does not access the diary store, write meals or measurements, apply targets, connect to Health or call the estimation server.

For Xcode Canvas previews, open `Recomp/Views/InterfacePreviewScreen.swift`. The supplied PreviewProvider includes light, dark, large-type and empty-diary cases. These previews still need to be compiled/rendered in Xcode.

For a visual reference without Xcode, open `Design/Reference.html` in a browser. It has a light/dark toggle, but its phone controls are deliberately non-functional. It is **not a web version of Recomp**. The adjacent PNGs show this reference, not native output. Native system materials, font metrics, controls and spacing may differ by iOS version and device.

## What changed

### Readouts, not a scorecard

Today has a large calorie readout, a thin ruler and a single aligned macro table. Logged values, targets and remaining/over-target amounts are explicit. Orange identifies actions and small markers; going over a target is not turned into a red alert. The three coloured macro cards and old ring-based visual language are removed.

Food history uses rows and rules instead of a separate floating card per meal. Small numbered section labels establish a hierarchy. Explanations and secondary controls remain available in native disclosure groups rather than dominating the first screen.

### Native interaction

The app still uses SwiftUI TabView and NavigationStack, system sheets and alerts, native Form/List editing, compact date pickers, menus, toggles, segmented controls, system photo selection and Swift Charts. There are no replacement tab-bar gestures, drawn imitation input controls or custom rotary knobs. Primary actions use the native bordered-prominent button style.

Weight curves still separate scales. Point symbols supplement colour so the two scale histories are not distinguished by colour alone. Units, source labels, untagged warnings, incomplete-data states and maintenance sensitivity caveats remain part of the interface.

### Typography and appearance

Body text uses the system font; measurements and totals use the system monospaced design. No font download or embedded font file is required. Large readouts use `@ScaledMetric`, with stacked arrangements for accessibility text sizes. Adaptive rows use `ViewThatFits`. The decorative ruler is not an accessibility control.

The colour catalogue supplies light/dark and increased-contrast variants. The selected foreground token pairs and primary-button label were checked against a 4.5:1 contrast threshold. That check is **not a full accessibility audit**; VoiceOver, actual control rendering, larger text and native chart behaviour still need device testing.

The icon is an original level-meter graphic using the same palette. It contains no photo, external font or brand mark.

## Where to find existing controls

| Task | Location in 1.4 |
|---|---|
| Enter a meal manually | Today → Log food |
| Photo or text estimate | Today → Estimate |
| Saved-food shortcuts | Today → Your usuals (expand) |
| Confirm that all food is logged | Today → Review complete day |
| Review imported nutrition | Today → Additional Apple Health nutrition (expand) |
| Log weight, body fat or tape readings | Body → Log measurements |
| Tag or manage scales | Existing scale/location selector and Body tag toolbar button |
| Connect measurement types | Body → Apple Health measurements (expand) |
| Inspect learned maintenance and proposals | Maintenance tab |
| Switch theme / inspect sample screens | Settings → Interface |

Only confirmed food estimates are saved. The photo upload confirmation, manual locks, refinement and undo remain; they were not replaced with an immediate upload or an automatic diary write. The estimator still needs the separately configured optional server.

## Data and upgrade

Version 1.4 is a presentation update. **All 24 original files in Core/, Services/ and Server/ are byte-identical to the supplied 1.3 archive.** See `Verification/domain-unchanged.log` for the comparison. Scale-aware maintenance math, diary persistence, Health receipts, target-review rules and the AI server have not been rewritten. Tests exercise those retained rules; they do not establish clinical accuracy or real HealthKit behaviour.

Diary schema remains **3**; there is no new diary migration. The only new preference is the appearance selection, stored separately in UserDefaults. The generated privacy manifest includes the app-owned UserDefaults reason `CA92.1`. This is not an App Store compliance sign-off, and appearance is not a cloud-sync feature.

Before updating, export your existing data. Keep the **same development team and bundle identifier**, then Run over the existing installation. **Do not uninstall first:** uninstalling loses local data. The source project still uses `com.example.recomp` by default; restore your own signing details in the new project. An actual in-place iPhone upgrade has not been tested.

## Development map

- `Recomp/Views/InstrumentStyle.swift`: shared typography, surfaces, colours, readouts and native style modifiers.
- `Recomp/Assets.xcassets`: adaptive palettes and the replacement app icon.
- `Recomp/Views/InterfacePreviewScreen.swift`: read-only in-app gallery and Xcode previews.
- `Design/AppIcon.svg`: editable original icon source.
- `Design/Reference.html`: labelled, non-functional visual reference.
- `scripts/check-interface.py`: source/asset checks, project membership and selected contrast pairs.

The project has already been regenerated with the two added Swift files. Regenerating with `python3 scripts/make_project.py` resets generated signing settings; reapply your team and bundle ID afterward.

## Verification

The portable Debug and Release suites each passed **168 tests**. The production DiaryStore harness passed **47 checks using test doubles**. The server suite passed **42 mocked-provider tests**. There are also **71 static interface checks**, plus Swift parser-only checks of all 30 app source files. None is an iOS UI test.

The browser reference was rendered in light and dark modes and checked at wide and narrow browser widths. This verifies that reference only, not the app's SwiftUI layout.

**Still unverified:** native iOS compilation, simulator launch, device installation/upgrades, real HealthKit, photo/camera flow, real AI responses, Dynamic Type/VoiceOver behaviour on Apple devices, and App Review. See `Verification/BUILD_STATUS.md` for the exact checklist and current logs.

## Design/API references

Reviewed September 18, 2026. References support the design direction and framework choices, not proof that this app builds or passes review.

- Teenage Engineering field system: https://teenage.engineering/products/field-system
- Apple layout guidance: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple Dark Mode guidance: https://developer.apple.com/design/human-interface-guidelines/dark-mode
- SwiftUI ScaledMetric: https://developer.apple.com/documentation/swiftui/scaledmetric
- Apple interface tips: https://developer.apple.com/design/tips/
- Required-reason API declarations: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
