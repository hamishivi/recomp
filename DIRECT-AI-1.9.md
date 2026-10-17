# Recomp 1.9 — direct AI, no server to operate

For installation and everyday use, start with **[setup.md](setup.md)**. It includes Xcode, signing, App Groups, iPhone Developer Mode, API-key setup, Health connections, backups, widgets and travel.

This remains an unsigned native iPhone source project. No Xcode/iPhone build or live OpenAI call was performed for this release. The portable and synthetic-network checks are documented in `Verification/BUILD_STATUS.md`.

## The two connection modes

**Direct · personal API key** sends each reviewed request from the phone to the fixed `https://api.openai.com/v1/responses` endpoint. You enter your own key on the phone. No Node service, tunnel, domain or always-on computer is needed for daily use. Internet access and separately billed OpenAI API access are still required; this is not on-device or offline AI.

**My server · advanced** retains the earlier HTTPS proxy route. Existing configured installations keep that mode until you explicitly change it; an empty configuration starts in Direct. There is no automatic fallback between connections. The optional `Server/` directory is unchanged from v1.8.

In **Settings → Photo & text estimates**, review the personal-key acknowledgement, paste a key into the secure field, select GPT-4.1 mini or GPT-4.1, then Save. Optional **Test connection…** requires confirmation and sends only a synthetic egg description. It is a paid API request, not a food entry; passing it establishes connectivity/schema compatibility, not nutrition accuracy. Testing does not save the configuration automatically.

## Same food workflow

Text descriptions, up to six resized photos, evidence roles/captions, ingredient breakdowns, manual value corrections, protected edits, refinement, undo, retained meal photos and Check-without-logging remain. Each estimate/refinement still needs an upload confirmation naming the destination. Only reviewed food entries are saved or exported to Health.

The direct path uses the same instructions and strict JSON schema as the proxy, checked independently by the local test provider. It requests a bounded, structured meal response with `store: false`, `stream: false` and at most 4,500 output tokens. Input is restricted to this meal's text, photos, current estimate, locked item IDs and excluded foods. It does not request web search, upload report files, create a hosted conversation or use previous-response IDs.

Your current daily totals, targets, body data, Health samples, DEXA reports, activity history, backups and other meals are not available to this request builder. Anything you deliberately type into the meal description or visibly include in a photograph is part of the request.

## Personal-key trade-off

OpenAI recommends a backend instead of placing API keys in mobile clients. This is an explicit convenience/security trade-off for a privately installed, personal-key app—not a production credential-distribution design. Never hardcode or distribute a shared key. See the official [API-key safety guidance](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety).

The app stores its configuration in a private `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain item, without an App Group or synchronizable attribute. It is not included in the diary, widget, source project or encrypted diary backup. Saving a different connection removes the inactive credential from that Keychain item. Credential debug descriptions redact the values.

Direct mode cannot send an API key to a user-supplied URL. Server mode rejects an OpenAI-format key in its proxy-token field. The HTTP client rejects redirects, uses an ephemeral session without cookies or persistent URL credentials/cache, limits response bytes, and has a fixed request deadline. None of this makes a key safe from a compromised app/device, software instrumentation or an exposed key copied elsewhere. This release is not a security audit, and it does not implement certificate pinning.

**Forget AI settings** deletes this local item, not the remote key. Keychain data can survive app reinstallation. Rotate/revoke keys in the API account when needed; review usage, restrict project/model permissions, and use actual enforced spending controls where supported. An alert alone is not an enforced spending cap. The client has no durable local daily quota and never treats a cancelled request as guaranteed free.

`store: false` is not a zero-retention promise. OpenAI's abuse-monitoring/data controls still apply. Images are processed by OpenAI, even though there is no server for you to host. The linked [API data-control documentation](https://developers.openai.com/api/docs/guides/your-data) governs the provider side.

## Failure behaviour

Invalid keys/configuration, too many or malformed image inputs and invalid refinement state are rejected before starting HTTP work. Input limits retain the proxy's text/image budget, including JPEG framing/dimension checks. Framing validation is not a full JPEG decoder; real photo preparation still uses Apple's image APIs and needs native testing.

Received JSON must fit the response limit, be a completed assistant response and contain a valid food breakdown. Refusals, incomplete output, malformed JSON, missing required fields and references to nonexistent photos are rejected. Protected items are restored from the reviewed local snapshot and the final result is validated again. The existing model leaves the editable draft unchanged after errors or cancellation.

Authentication, permission, quota, model/request and service failures have sanitized messages. Raw provider error/refusal text is not shown. There are no automatic paid retries or model fallbacks. The ordinary upload and connection-test screens prevent duplicate submission while active, but repeated deliberate requests are separate paid requests.

## Update and implementation map

Version **1.9**, build **12**, diary schema **7**. The diary schema, maintenance algorithm, travel clocks/coverage, Health sync state machine, DEXA rules, widget and backup format are unchanged. Preserve the existing app bundle ID, App Group and signing team; install over the existing app after retaining a verified backup/original reports.

- `Core/EstimatorConfiguration.swift`: mode, migration, credential/endpoint validation, model choice and redacted debug description. Encoded only for Keychain.
- `Core/DirectAIContract.swift`: Responses request, instructions/schema, bounds, response validation and manual-lock restoration.
- `Services/EstimatorKeychain.swift`: existing private Keychain identity, now holding either connection mode.
- `Services/EstimationService.swift`: direct/proxy dispatch over the retained bounded HTTP client.
- `Views/EstimatorSettingsView.swift`: native connection selector, secure key entry, explicit risk acknowledgement, billable test confirmation and forget controls.
- `Tests/RecompCoreTests/DirectAITests.swift`: 26 new executable portable tests.
- `TestSupport/DirectAIHarness/` and `scripts/check-direct-ai.sh`: production client and transport against a strict synthetic local provider; no paid request.

## Run the checks

```bash
# Full portable suite + localhost HTTP fixtures (Node 22+ needed only for tests):
./scripts/check.sh

# Focused direct connection checks:
swift test --filter DirectAITests
./scripts/check-direct-ai.sh
ASAN_OPTIONS=detect_leaks=0 RECOMP_DIRECT_ASAN=1 ./scripts/check-direct-ai.sh

# macOS + full Xcode, no Node needed for this native-only gate:
./scripts/check-native.sh
```

The supplied native test target includes the new portable core cases, but it has not been executed with Apple's SDK for this release. It does not yet provide an automated native Keychain lifecycle test or a live Responses API test. See the current verification report and device acceptance checklist before relying on the app for your only records.
