# Verification — Recomp 1.9 direct AI

**Tested source change, not a verified native iPhone build.** Executed September 18, 2026 on Linux x86_64, Swift 6.2.1 and Node.js 22.16.0. No macOS/Xcode, Apple SDK, simulator, paired iPhone, actual Health/Keychain store, private API key or live OpenAI request was used.

Version **1.9 / build 12 / schema 7**. Input: `Recomp-Travel-v1.8.zip`. Historical reports under the other Verification directories describe earlier runs, not additional new tests.

## Checks actually completed

| Check | Result | Scope |
|---|---:|---|
| Original v1.8 core baseline | **339 passed** | Establishes the unchanged baseline before this edit. |
| Full current portable gate, `./scripts/check.sh` | **Exit 0** | Runs the current Debug/Release, controller, travel, HTTP, Node and static suites below. Explicitly reports that no native build ran. |
| Swift core, Debug | **365 passed, 0 failures** | 339 retained methods + 26 direct-AI configuration/request/response tests. |
| Swift core, Release | **365 passed, 0 failures** | Same methods with an optimized Linux build, not an iOS Release build. |
| DiaryStore coordinator | **134 checks passed** | Production coordinator, temporary files and a fake Health adapter. |
| Meal estimator model | **17 checks passed** | Actual model, synthetic network and observation support. |
| Retained first / second bug-pass harnesses | **20 / 17 passed** | Existing sync races, pause, disk failures and edit regressions. |
| Travel coordinator and legacy diary replay | **36 checks + 7 process executions passed** | Actual store/filesystem, simulated timezones, fake Health. |
| Retained proxy-route HTTP client | **24 checks passed** | Production configuration/service/transport, localhost responses, no paid provider. |
| New direct-route HTTP client | **25 checks passed** | Actual direct request/validation and bounded transport against a strict synthetic provider. |
| Direct-route AddressSanitizer | **25 checks passed** | `ASAN_OPTIONS=detect_leaks=0`; leak detection explicitly disabled. No detected address errors in these cases, not a security audit. |
| Optional server unit / localhost suite | **65 tests passed** | Provider is mocked; `Server/` source is unchanged. |
| Static interface / feature / DEXA checks | **96 / 99 / 25 passed** | Source/configuration and selected asset checks, not native UI behaviour. |
| App/widget/native-test Swift parsing | **57 files passed** | Parser only, not Apple-SDK type checking. |
| Plists, entitlements and privacy manifest parsing | **Passed** | Configuration syntax, not App Review approval. |
| Native gate attempt | **Unavailable, exit 2** | Explicit failure because macOS/Xcode are absent; not counted as a passing test. |

The repeated Debug/Release and sanitizer runs are not added together as unique tests. Earlier seeded arithmetic/scale/sleep/itinerary scenarios remain inside the retained core methods. There is no new full-core AddressSanitizer run for this release; the new sanitizer execution is specifically the direct network harness.

## What the direct-AI tests establish

The 26 portable methods exercise empty/direct defaults, backwards-compatible server configuration, unknown mode/model rejection, fixed OpenAI endpoint, explicit key acknowledgement, whitespace/HTTP-header validation, inactive credential removal, round trips and redacted debug descriptions. They also cover text-only and six-image request shapes, numbered evidence, model selection, bounds, invalid locks/images, truncated JPEG headers, strict completed-response decoding, refusals, missing/unknown fields, numeric validation, duplicate item IDs, invalid photo references, restored locked values and final item-count limits.

The 25 direct HTTP checks execute the production `EstimationService`, `DirectAIContract` and `BoundedHTTPClient`. A test-only injected transport checks the fixed OpenAI URL and synthetic authorization header, then reroutes the request to localhost. The fixture independently compares the request against the original Node proxy's schema/instructions and exact input whitelist. No request is sent to OpenAI, and no actual key is used.

Cases include text and six-photo success; HTTP 400/401/403/404/413/429/500; wrong content type; oversized or invalid responses; incomplete/refused output; invalid photo references; redirects; invalid inputs producing no request; cancellation; protected manual edits; recovery after failures; and exactly the expected request count with no retries/fallbacks. Redirect destinations receive neither a request nor a key. Error checks reject raw synthetic private provider text.

These tests do **not** establish that a real vision model reads food labels accurately, that a sample JPEG fixture decodes in UIKit, that the current account can use a chosen model, or that Apple's URLSession/Keychain match Linux Foundation behaviour.

## Preserved functionality and privacy checks

All previously existing Core/Services files are byte-identical to v1.8 except `Core/MealEstimate.swift` (the unconfigured-connection message) and `Services/EstimationService.swift` (connection dispatch and extraction of configuration/Keychain code into new files). In particular, Health sync, storage/migration, backup payload/crypto, travel and maintenance algorithms were not rewritten. New standalone files implement direct AI. The entire optional server directory is byte-identical to the input archive.

The source checks verify a private device-only Keychain attribute and no estimator configuration/API-key field in diary, widget or backup payload code. These are source-level checks, **not execution of secure storage or proof of non-extractability**. Current view code uses secure key entry, an explicit personal-key warning, separately confirmed testing/upload, and clears credential view state when it disappears.

## Evidence

Current logs are under `Verification/Direct-AI-1.9/`:

- `baseline-core.log` and `.exit`: unmodified 339-method baseline.
- `full-gate.log` and `.exit`: current full portable gate, including both 365-method runs and all retained/new harnesses.
- `direct-core.log`: focused 26-method run.
- `direct-network.log` and `.exit`: first focused direct HTTP run; the full gate repeats it using the final deterministic cancellation fixture.
- `direct-asan.log` and `.exit`: final direct network AddressSanitizer execution with leak detection disabled.
- `source-checks.log`: source parsing/configuration, selected byte comparisons and credential wiring checks.
- `native-attempt.log` and `.exit`: explicit unavailable-Xcode result.

Intermediate/initial logs show development stages, not additional unique test counts. No new report claims a real iPhone test, signed install, live provider connectivity or health/fitness model validation.

## Native acceptance checklist — still to run

1. On a Mac with full Xcode and an iOS 17+ runtime, run `./scripts/check-native.sh`. Resolve native compiler/SDK issues before installing on the phone. Build both the app and widget. Use `setup.md` for signing and App Group configuration.
2. In an isolated simulator, open Photo & text estimates. Confirm Direct default for empty settings and server preservation for an existing configuration. Check secure key entry, cancellation, acknowledgements, load-failure retry and no credential in screenshots/logs.
3. Test actual Keychain save/relaunch, remove, switching modes and restoration. Confirm old server configuration migrates without an automatic request. Never put a real key into a committed test fixture.
4. With your own dedicated API project and billing, explicitly approve one connection test. Verify one valid response and no diary entry/Health write. Failure/permission/quota messages should be actionable and not echo provider content.
5. On the phone, test a real food/label image and text-only estimate, six photos, manual protected edits/refinement, cancellation, network loss and Check without logging. Review label extraction/portions manually.
6. Back up and install over an existing diary using the same bundle ID/team/App Group. Confirm clocks, scale labels, DEXA results, history and widget are retained. No diary migration is introduced by 1.9; actual device upgrades remain unverified.
7. Check real HealthKit, backup encryption/restore, widget rendering/privacy, camera/PDF flows, Dynamic Type and VoiceOver. These existing native acceptance items have not become verified merely by adding direct networking.

The personal-key approach is an explicit trade-off against OpenAI's recommended backend design. It is not suitable for embedding a shared API key in a distributed app. No App Store compliance sign-off, secure-memory guarantee, certificate-pinning claim or clinical validation is provided.
