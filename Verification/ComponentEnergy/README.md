# Component energy verification

17 October 2026. All diary and screenshot fixtures here are synthetic. Device backup files, provisioning profiles, signed apps and personal data stay outside Git.

- Core: **474 tests passed** in Debug and Release, including **27 component-energy tests**. Command: `swift test --build-system native --scratch-path .build-energy-tests` (also `-c release`).
- Real persistence/coordinator harness: **148 checks passed**, including settings round trips, rejected inputs, unchanged food targets, no Health writes and excluded/overlapping food-coverage handling.
- Composer **70**, polish **41**, audit **38**, and second audit **17** checks passed. Travel/time-zone checks passed.
- Native backup cryptography **9** checks and paired Wi-Fi sync checks passed.
- Interface, UI refresh, polish and feature/project-wiring source checks passed.
- iOS 27 simulator: chart selection/forecast, completed/upcoming days, missing-input fallback, dark largest accessibility text, four-component disclosure, manual override persistence and invalid-value Save gating passed. The Form switch exposes its full row as an accessibility frame; the test targets the visible trailing switch control. That correction affected the test, not production behavior.
- A clean signed **Release app and widget** built successfully. Strict signatures passed for both bundles; all signed entitlements match the installed app. Profile expiry remains 24 October 2026 at 1:21 PM PDT.

Screenshots include the synthetic component chart, dark largest-text chart/header, manual settings and expanded breakdown. Native test bundles and full logs are retained locally under `/tmp/recomp-energy-*.xcresult` and `/tmp/recomp-energy-*.log` for this run; they are not durable research or deployment evidence. The source tests and these screenshots are the reproducible record.

These checks verify software behavior. They do not validate individual metabolic accuracy. See [research and limitations](../../Documentation/Audits/2026-10-17-component-energy-model.md).
