> Historical photo checklist from before version 1.7. Photo retention, six-image support and Check mode are covered by FEATURES-1.7.md and the current BUILD_STATUS.md.

# Verification — Recomp 1.1 photo + text update

**This is an unsigned Xcode source project, not an installed or App Store app.**

## Actually run for this delivery

Environment: Linux x86_64, Swift 6.2.1, Node.js 22.16.0.

| Check | Result |
|---|---|
| Portable Swift package | **62 tests passed, 0 failures**: 38 original + 24 estimation tests |
| Node unit + local HTTP tests | **42 passed, 0 failures**, with mocked AI provider |
| Swift parser over all 18 app source files | Passed; parser only, **not an Apple SDK type-check** |
| Generated Xcode source membership | All 18 Swift files included |
| Info.plist, privacy manifest, entitlements | Parsed; camera purpose included; no arbitrary-load, microphone or full-library permission |
| Node source syntax | Passed |
| Shell setup/check script syntax | Passed |
| Python project-generator syntax | Passed |

Full logs: `core-tests.log`, `server-tests.log`, `source-checks.log`.

Swift coverage added: component arithmetic and half portions, invalid-number/text/ID checks,
empty-food responses, locked-item preservation/restoration, removals, context/food limits,
optional-field backwards decoding, new diary round trips without photos/credentials,
rejection of stale aggregate-vs-item totals, limited request fields, and endpoint validation.

Node coverage includes real local HTTP requests to the proxy using a **fake provider**:
authentication, content/body limits, quota limiting, unknown routes, input validation,
JPEG-header/size checks, strict Responses payload generation, sanitised provider failures,
no-store request flag, refusal/truncation handling and deterministic locked-item restoration.
No live API key was supplied, no paid AI request was made, and tests do not measure food
recognition or nutritional accuracy. The JPEG header fixture tests the size/container guard,
not a complete image decoder or vision model.

## Not verified here

- Native SwiftUI/UIKit/PhotosUI/AVFoundation/Security/HealthKit compilation or launch.
- Real-device signing, camera/Photos permission flows, orientation/metadata removal at runtime,
  keyboard/layout/accessibility and nested-sheet dismissal.
- Live OpenAI model availability for your account, response quality, token use or charges.
- HTTPS deployment, certificate trust, device-to-server networking, production hosting/logging.
- Real HealthKit authorization, writes, edits/deletions, or visual deduplication in Apple Health.
- GitHub Actions, Docker build or App Review. Included workflows/configs have not been run on
  external services. No claim of deployment, on-device success or App Store compliance.

The project’s existing `scripts/check.sh` runs Swift and Node tests and, **on a Mac with
Xcode**, attempts an unsigned iOS Simulator build. The included macOS GitHub Actions workflow
will do the same after you upload/trigger it; it has not been triggered in this delivery.

## Device acceptance checklist

1. Build Debug for iPhone and Simulator in Xcode; resolve any SDK/compiler issues.
2. Update in place using the existing bundle ID/team. Confirm a 1.0 diary still loads.
3. With no estimator configured, verify manual logging/Health continue working and AI setup
   gives a useful error; no silent transmission or fake estimates.
4. Deny camera permission, then select a library photo or type a meal. Verify the Settings
   recovery path, camera cancellation, and simulator camera-unavailable message.
5. Test portrait/landscape/HEIC/large and rotated photos. Inspect uploaded JPEG dimensions and
   metadata: <=1600 px longest edge, <=1.5 MB each, no original GPS/EXIF. Verify three-photo cap.
6. Set up the proxy with your own key and HTTPS. Verify no request before the explicit send
   confirmation; destination host and payload disclosure must be visible.
7. Estimate a known-label food and a mixed meal. Check editable components, total arithmetic,
   visible assumptions, question-only/no-food responses and uncertainty labels.
8. Refine “half the rice”, then “the chicken was grilled”: ensure rice is not halved again.
   This language behaviour requires live model checking; deterministic totals alone cannot
   establish it. Correct inaccurate results before logging.
9. Manually change a food’s label values, keep it locked, refine another item, and verify the
   edited values survive. Unlock and refine it. Check missing/removed foods and Undo.
10. Test add/remove, portion multipliers, invalid/empty numeric fields, long text and no-food
    results. Saving should remain disabled for an invalid or empty-nutrition meal.
11. Confirm a draft: exactly one diary entry should be saved. Ensure tapping save again cannot
    create a second entry. Reopen “Refine food breakdown”, save and verify the same meal updates.
12. With Health on and chosen write permissions, only confirmed calorie/macronutrient totals
    should be exported. Photos and AI details must not appear in Health metadata. Check edits
    replace prior app samples and preserve original deduplication/permission behaviour.
13. Disconnect network, use a wrong token, exhaust proxy quota, trigger a server/provider error
    and cancel a request. Existing draft/diary must remain intact and manual editing must work.
14. Close without saving and reopen. The diary should be unchanged; photos/unsaved drafts are
    deliberately not retained. Saved text/components should survive app restart without photos.
15. Save aggregate-only macro edits in the original food editor. Confirm the stale AI
    breakdown is removed and no invalid diary state is persisted.
16. Forget the server token, rotate it server-side, and inspect deployment logging/retention
    settings. Review privacy manifest and App Store declarations against the actual deployment.

## Scope

Manual entry, targets, saved foods, CSV, trends and opt-in foreground Health sync are retained.
AI inference requires the configured server and separate API billing; no server, API credit,
background inference or installable signed app is bundled. Public multi-user deployment needs
proper per-user authentication, persistent quotas and a security/privacy review.
