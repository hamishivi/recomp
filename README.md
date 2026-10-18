# Recomp

A native SwiftUI app for food logging, body measurements, and estimated energy expenditure. Includes an iOS widget, optional Apple Health integration, and optional AI-assisted food estimates.

## Features

- Food diary with calorie and macro totals, searchable meal history, saved foods, and reviewed photo/text estimates.
- Weight, body measurements, and DXA records, with comparisons that respect different scales.
- Maintenance estimates from complete food logs and comparable weight trends.
- An interactive calorie-burn chart with estimated burn, a day forecast, maintenance reference, and workout markers.
- Local storage, optional sync, and encrypted backup/restore.
- Light/dark appearance, Dynamic Type, and an isolated interface preview with sample data.

## Build and run

1. Clone this repository and open `Recomp.xcodeproj` in Xcode.
2. Select the **Recomp** scheme and an iPhone simulator with iOS 17 or later, then Run.
3. For a physical device, configure your own development team, bundle identifiers, capabilities, and App Group as described in [setup.md](setup.md).

The local diary and interface previews work without an AI server or API key. Enable Apple Health connections separately if desired. To explore the chart without personal records, open **Settings → Interface preview → Burn**.

For an existing installation, preserve its bundle identifier, signing team, and App Group. Export a backup and install over the app; uninstalling removes local records.

## Meal history

Open **Log food → Meal history** to search all previously logged meals, newest first. Search matches names, ingredients, portions, meal types, and notes, including older records. History is separate from **Your usuals** and needs no migration.

Choosing a meal fills the current draft for review; it is logged only when you press **Save**. The ingredient breakdown and estimate status are retained. The current date, meal type, notes, and photos stay in place, and **Undo** restores the previous food. Historical photos and Health export receipts are never copied. The original record stays unchanged; deleted meals and the entry currently being edited are excluded.

## Calorie-burn model

With suitable body composition or a manual resting value, the chart estimates resting metabolism (RMR), everyday movement (NEAT), exercise above rest, and digestion (TEF). Settings → Energy model shows the source and editable assumptions. Automatic RMR uses existing fat-free-mass data; no demographic fields are required. Suitable food, weight and activity history can calibrate the untracked movement allowance, with its uncertainty explained in the chart. Missing resting input retains the maintenance/activity fallback.

The chart does not use Apple's resting- or active-calorie estimates. Burn so far is separate from future forecasts, and overlapping steps/workouts count once. Food targets do not automatically increase with exercise. These are approximate fitness estimates: body composition, intensity, device coverage, food errors, water-weight changes and defaults affect accuracy. Tests establish software behavior, not individual physiological accuracy. See [the research, equations and limitations](Documentation/Audits/2026-10-17-component-energy-model.md).

## Optional AI estimates

Food estimates must be reviewed before saving. Configure direct AI in the app, or use the optional [Node.js estimation proxy](Server/README.md). The proxy requires Node.js 22 or later; copy `Server/.env.example` to `Server/.env` and supply your own credentials. Never commit API keys or access tokens.

## Verification

```sh
# Core calculation and data-model tests
swift test
swift test -c release

# Full regression and native simulator acceptance gate (macOS + Xcode)
./scripts/check.sh --require-native
```

The October 17, 2026 chart update passed 442 core tests in both Debug and Release, 158 interface/source checks, and two focused iPhone simulator UI tests. The simulator Release app/widget build also passed. Chart screenshots were checked in light appearance and dark appearance with the largest accessibility text size. These checks do not establish real-world energy accuracy or replace a complete device accessibility audit.

The subsequent [meal history update](Verification/FoodHistory/README.md) passed 447 core tests in both Debug and Release, 70 composer checks, 41 composer polish regressions, 158 interface/source checks, and four focused iPhone simulator UI cases. Debug simulator and signed Release iPhone app/widget builds passed; the history picker was checked in light appearance and dark appearance with the largest accessibility text size.

Build products, raw local diagnostics, device metadata, personal diary exports, and credentials are excluded from Git. Files under `Examples/` and the backup interoperability fixture contain synthetic test data. Older verification reports describe their original versions; referenced raw logs remain local.

## Documentation

- [Setup, signing, Health, and AI configuration](setup.md)
- [Calorie-burn model and chart review](Documentation/Audits/2026-09-25-activity-expenditure.md)
- [Diary schema 8 and sync audit](Documentation/Audits/2026-09-25-third-pass.md)
- [Version 1.10.1 interface notes](POLISH-1.10.1.md)
- [Historical build and verification notes](Verification/BUILD_STATUS.md)

## License

[MIT](LICENSE).
