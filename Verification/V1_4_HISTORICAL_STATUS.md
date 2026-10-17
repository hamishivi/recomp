# Verification — Recomp 1.4 instrument interface

**Unsigned Xcode source project. No native iOS SDK build, simulator launch or iPhone test was performed.**

## Checks actually completed

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0; September 18, 2026.

| Check | Result and limit |
|---|---|
| Portable Swift package, Debug | **168 tests passed, 0 failures**, rerun for this delivery |
| Portable Swift package, Release | **168 tests passed, 0 failures**, rerun for this delivery |
| Production DiaryStore with labelled portable test doubles | **47 coordinator checks passed**; not real Combine/HealthKit |
| Node unit/local HTTP suite | **42 tests passed**; mocked AI provider, no paid/live API request |
| Static interface checker | **71 checks passed**: selected contrast pairs, asset declarations, native-control code paths, new preview isolation, project membership and privacy reason |
| Swift source parser | All **30** app source files parsed, normal and DEBUG branches; **not native type checking** |
| Property lists and Xcode shared-scheme XML | Parse/consistency checks passed; source membership includes both new Swift files |
| Shell, Python and Node source syntax | Passed |
| Retained domain implementation | All **24** Core/, Services/ and Server/ files byte-identical to the supplied v1.3 archive |
| HTML visual reference | Rendered with Chromium/Playwright in light and dark modes; images inspected, no page script errors, no document-level overflow at a 390-pixel browser viewport. **Not an app UI test** |
| Combined check script | Portable checks completed; explicitly reported that no native build was performed on Linux |

The project is version **1.4, build 5**. Diary schema remains **3**. The appearance preference is separate app-owned UserDefaults; no new health permissions or AI request fields were added.

Current logs: `core-tests.log`, `release-core-tests.log`, `store-checks.log`, `server-tests.log`, `interface-checks.log`, `source-checks.log`, `domain-unchanged.log`, `reference-checks.log`, `full-check.log`.

The static checker verifies selected Ink/Muted/Accent foregrounds against Canvas/Panel and the primary button label against Signal at 4.5:1 or greater in all four asset variants. It does not inspect every state of native system controls and is **not a full accessibility or WCAG conformance assessment**. Source-pattern checks are structural assertions, not behavioural or visual tests.

The HTML and PNG files in `Design/` are design references with synthetic values, not captured SwiftUI rendering. They do not prove that the native layout is pixel-identical or that any iOS screen compiled. The in-app gallery does use the real native components, but still needs to be built in Xcode.

## What is retained, not newly validated

Core tests retain the prior coverage of diary migration/persistence, calculation arithmetic, source-aware Health deduplication rules, day completion, guarded maintenance proposals, scale tagging, within-scale trends and synthetic data isolation. The coordinator harness uses the actual store with mocked adapters; it cannot prove HealthKit permissions, units, replacement/deletion or lifecycle behaviour.

The redesigned UI keeps review-before-upload/log/apply, clear unlearned starting guesses, sensitivity-range caveats, per-scale separation, explicit missing-data states and local storage. The existing maintenance heuristic is still unvalidated; passing tests does not establish real metabolic accuracy or fitness suitability.

## Still unverified

- Native SwiftUI, Charts, UIKit, HealthKit, PhotosUI, AVFoundation and Security type checking/linking or launch.
- Xcode signing, simulator/phone installation and in-place update/data retention on a real device.
- Real camera, Photos, Health read/write permissions, sample replacement, scale import tags and sync behaviour.
- Live model estimates, configured HTTPS hosting, billing or cancellation at the provider.
- Native layouts, chart legends, forms, dark/light/increased-contrast rendering, large text, VoiceOver, keyboard and sheet interactions.
- App Store/TestFlight distribution, privacy-policy compliance, App Review or medical validation.
- The included Mac GitHub Actions workflow has not been run here.

## Native acceptance checklist

1. On a Mac with Xcode, run `./scripts/check.sh`, then build Release as well. Resolve any Apple-SDK errors before device use.
2. Export existing records. Update using the same bundle identifier/team without uninstalling; check food, estimates, scales, measurement tags, targets and sync queues still exist. Version 1.4 should keep schema 3.
3. Settings → Interface: test System/Light/Dark, change system appearance and reopen. Check contrast with the iOS Increase Contrast setting; ensure orange button labels remain readable in enabled/disabled/pressed states.
4. Inspect the read-only interface gallery and Xcode previews. It must not create diary records, Health writes or target changes. Verify the real empty diary stays empty.
5. Test small iPhones, landscape, all Dynamic Type sizes, bold text and VoiceOver. Check that macro columns adapt without hiding values, disclosures announce their state, decorative ruler marks are not focusable and tappable items are large enough.
6. Today: previous/next/date selection, manual entry, saved foods, edits/deletes, over-target/empty states, complete-day review/invalidation, extra Health nutrition and pending/error messages.
7. Photo estimation: select/take a photo, confirm upload, refine text, lock/unlock items, undo, cancel and save. No request or diary/Health write should happen without its existing confirmation path.
8. Body/Trends: test all and single scale filters, symbols, separate lines/rolling averages, long tag names, kg/lb and cm/in, body-fat methods, history editing, imported tags and the measurement Health disclosure.
9. Maintenance: insufficient data, starting guess vs learned estimate, scale notices, sensitivity label, window/limitations disclosure, proposal opt-in/review/apply and cooldown. The design change must not suppress safeguards.
10. Check all native forms, keyboard dismissal, date and unit controls, confirmations, cancel actions, navigation back, tab state and real-device Health behaviour.

Previous reports remain in `V1_2_HISTORICAL_STATUS.md` and `V1_3_HISTORICAL_STATUS.md`. Prior logs replaced for this delivery were retained under `Historical/1.3/`; they are historical, not current-run evidence.
