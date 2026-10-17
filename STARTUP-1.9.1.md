# Recomp 1.9.1 — Xcode warnings and launch-work fixes

This is a source patch for v1.9, not an independently verified iPhone build. Your reported messages are warnings; none of the messages supplied was a compiler error. They do not, by themselves, identify why your simulator launch is slow.

## Update without redoing signing

Use the separately supplied `Recomp-v1.9.1-Patch.zip` to update an existing v1.9 project. Quit Xcode first. After unzipping the patch into Downloads:

```bash
# Inspect only; your project path may differ.
python3 ~/Downloads/Recomp-v1.9.1-Patch/apply.py "$HOME/Downloads/Recomp 5"

# Apply after the dry run succeeds.
python3 ~/Downloads/Recomp-v1.9.1-Patch/apply.py "$HOME/Downloads/Recomp 5" --apply
```

Select the directory containing `Recomp.xcodeproj`, not the inner source directory. The updater checks all source hashes before writing, saves original source files under `.recomp-update-backups/`, and preserves bundle identifiers, teams, App Groups and schemes. It stops rather than overwriting an unexpected Swift source edit. It does not read credentials, access an app's diary container or install/uninstall anything. The rollback folder is a **source backup**, not a backup of your app data. Keep your normal diary backups as well.

Reopen the **same** Xcode project and Run. Installing over the same app retains its identity. Do not uninstall the app or erase the simulator to apply this patch. No new permissions, server deployment, database schema or AI key changes are required.

A full updated project ZIP is also available; it uses example signing identifiers. The in-place patch is easier when signing has already been configured.

## What each warning means

### `not stripping binary because it is signed`

The build is declining to remove debug symbols from an already signed embedded product. It is not saying signing failed. The `.debug.dylib` and `__preview.dylib` filenames are part of Xcode's modern unoptimized app/extension layout, not unexpected extra apps.

The project now explicitly sets **Strip Debug Symbols During Copy (`COPY_PHASE_STRIP`) to No for Debug**. Signing, extension embedding, debug symbols and Xcode Previews remain enabled. We have not reproduced your exact Xcode toolchain, so this is not a guarantee that all such copy-stage notices disappear. Do not manually strip signed files or disable signing to silence the warning.

### Unused `withUnsafeMutableBytes` result

`BackupCrypto.swift` now explicitly discards the result of its best-effort buffer-clearing call:

```swift
_ = keyBytes.withUnsafeMutableBytes {
    $0.initializeMemory(as: UInt8.self, repeating: 0)
}
```

This does not change the key derivation, encryption format or password rules. It does not claim secure memory zeroization against all compiler/runtime copies.

### Missing document-opening policy

`Recomp/Info.plist` and its generator now explicitly declare:

```xml
<key>LSSupportsOpeningDocumentsInPlace</key>
<false/>
```

Recomp imports/reads reports and backup contents; it does not coordinate in-place editing of your original provider files. Use the import buttons inside Recomp for PDFs and backups. This is not a new document-browser feature.

## Launch/rendering work reduced

- **One JSON parse instead of two** when loading a diary. Schema inspection shares the `JSONDecoder` parse instead of allocating a second Foundation dictionary tree containing all the photos/PDFs. Validation and atomic legacy migration remain.
- **One selected-day key/interval per diary query**, instead of reconstructing the same calendar/date string for every food record. Captured travel dates, legacy fallbacks and Health exact-ID deduplication remain.
- **One maintenance fit per screen rendering pass** rather than separately recalculating it for the summary and recommendation labels. No stale proposal is cached across changes.
- **Overlapping start/foreground callbacks are coalesced**, instead of queuing a duplicate Health refresh. Real food/measurement edits still request a queue drain.
- **Unchanged widget values aren't repeatedly written/reloaded** for every Health receipt and minute tick. Privacy changes, new values, dates, timezones, missing files and failed writes still require publication. iOS controls actual widget rendering and refresh delivery.

These remove identified work; they do **not** establish that this work caused the delay you saw, especially with a new empty diary. Large JSON diaries still load synchronously and retained attachments still live in that file. This is not a complete background-storage redesign.

## Isolate the simulator delay

1. Build/install once, then press Xcode's **Stop** button. Open Recomp by tapping its icon on the simulator Home Screen. Compare that with pressing Run in Xcode. This separates app launch from building, installing and debugger attachment.
2. In Simulator versions exposing it, check **Debug → Slow Animations** is off. Slow animations affect animation playback, not Swift compilation or file loading. Menu organization differs between Xcode/Simulator versions.
3. Compare an actual iPhone launch before concluding simulator speed represents device performance. For production-like performance, profile an optimized Release build; keep ordinary Debug builds for debugging.
4. When the app itself still delays before becoming responsive, use **Product → Profile**, then Instruments' **App Launch** template to locate the blocking work. Don't delete your diary just to benchmark it.

An additional simulator-only `RecompUITests.testLaunchPerformance` records `XCTApplicationLaunchMetric(waitUntilResponsive: true)` over five launches of an isolated empty test diary. It adds no Health or AI connection. Run it from the Test navigator or the existing gate:

```bash
./scripts/check-native.sh
```

It has **not run in this Linux environment**. It provides a native measurement to collect, not a promised launch-time number. Existing UI tests remain.

## Tests and measurements

See `Verification/Startup-1.9.1/REPORT.md` for actual results and limitations, and that directory's raw logs. Timing benchmarks use synthetic data, the same Linux Swift toolchain and optimized core executables. They are not simulator/iPhone frame-rendering measurements.

```bash
swift test
./scripts/check-startup.sh
# Full retained developer gate (Node needed for mocked HTTP suites):
./scripts/check.sh
# macOS + full Xcode, needed for actual native build/tests:
./scripts/check-native.sh
```

No maintenance formula, target heuristic, direct-AI contract or Health sample format is changed.

## Apple references

Reviewed September 18, 2026; these document framework/build behavior, not successful testing of this app.

- Debug dylib layout: https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes
- Build settings: https://developer.apple.com/documentation/xcode/build-settings-reference
- Document-opening policy: https://developer.apple.com/documentation/bundleresources/data-and-storage
- Launch profiling: https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time
- Native launch metrics: https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric
- Simulator debugging (archived menu reference): https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/iOS_Simulator_Guide/TestingontheiOSSimulator/TestingontheiOSSimulator.html
