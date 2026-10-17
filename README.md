# Recomp

A native SwiftUI app for food logging, body measurements, and estimated energy expenditure. Includes an iOS widget, optional Apple Health integration, and optional AI-assisted food estimates.

## Features

- Food diary with calorie and macro totals, saved foods, and reviewed photo/text estimates.
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

## Calorie-burn model

The chart estimates background expenditure, walking outside workouts, and net workout expenditure using weight, steps, and workout records. It does not use Apple's resting- or active-calorie estimates. It separates expenditure so far from future activity forecasts and avoids counting overlapping steps/workouts twice.

These are approximate fitness estimates, not measured metabolism. Activity intensity, incomplete device coverage, food logging errors, water-weight changes, and provisional defaults affect accuracy. The tests establish software behavior, not physiological accuracy. See [the model, assumptions, and limitations](Documentation/Audits/2026-09-25-activity-expenditure.md).

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

Build products, raw local diagnostics, device metadata, personal diary exports, and credentials are excluded from Git. Files under `Examples/` and the backup interoperability fixture contain synthetic test data. Older verification reports describe their original versions; referenced raw logs remain local.

## Documentation

- [Setup, signing, Health, and AI configuration](setup.md)
- [Calorie-burn model and chart review](Documentation/Audits/2026-09-25-activity-expenditure.md)
- [Diary schema 8 and sync audit](Documentation/Audits/2026-09-25-third-pass.md)
- [Version 1.10.1 interface notes](POLISH-1.10.1.md)
- [Historical build and verification notes](Verification/BUILD_STATUS.md)

## License

[MIT](LICENSE).
