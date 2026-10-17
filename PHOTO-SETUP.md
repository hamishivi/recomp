# Photo + text food estimation — optional SERVER route

**v1.9:** For direct personal-key setup without hosting anything, use **[setup.md](setup.md)**.
Everything below that describes a server applies only to **My server · advanced**.
The photo/editing workflow is shared. Direct mode calls OpenAI on the phone and does not
need `Server/`, `.env`, Node, HTTPS deployment or `RECOMP_ACCESS_TOKEN`.
The key-storage/privacy difference is explained in `DIRECT-AI-1.9.md`.


**Interface update in 1.4:** see [DESIGN.md](DESIGN.md) for the new appearance and navigation. Food estimation is now **Today → Estimate**; food-day confirmation is **Review complete day**; measurement Health controls are inside **Body → Apple Health measurements**. The implementation and safety details below are retained.

Version 1.2 retains this photo-estimation workflow. Body measurements and maintenance run locally without the AI server; see `BODY-MAINTENANCE.md`.

## What you can do

**Today → Estimate** opens a draft. Take a picture, select up to six
images, or type a description. A second image can show another angle or the package label;
tell the app when the images show different foods rather than the same plate.

Tap **Estimate meal**, review the upload confirmation, then review the food breakdown.
The numbers are for the amount eaten, not per 100 g. The model has no food database or
web search and cannot reliably see hidden oil, exact portion weight or unreadable labels.
It lists assumptions and important questions instead of claiming precise measurements.

**Refine with more details**, for example:

> “This was the Little Thai chicken combo. I ate half the rice, all of the chicken,
> and only one spring roll. There was about a tablespoon of oil in the whole meal.”

The next request includes the **current edited snapshot**, previous food context and your
new correction. It asks the model not to apply earlier corrections twice or recreate
removed foods. These language-based instructions are not a mathematical accuracy guarantee;
review every revision. Nutrition totals themselves are summed deterministically from items.

**Edit** on a food lets you change its name, portion description, calories or any macro.
“Half”, “Double”, or a custom multiplier scales all four nutrient values. Changing a
portion description alone does not recalculate values. Manual edits default to **Protect
from AI changes**; both client and server restore locked items even if the model changes or
omits them. Tap the lock to let AI refine that item. Add and remove components as needed.
A “before/change” calorie line and **Undo last change** help review refinements.

Only **Log meal** saves the draft. With Health enabled, only the confirmed calorie,
protein, carbohydrate and fat totals are queued for Health. After logging, tap the meal,
then **Refine food breakdown** to update the same record. Reopened meals retain text, items and any resized photos you chose to keep. The same meal ID/versioning
path replaces its Health exports instead of intentionally adding a second meal.

Editing only the aggregate macros in the original manual editor and saving deliberately
removes a stale AI breakdown. “Your usuals” saves the aggregate food shortcut, not an AI
conversation. CSV export remains the original aggregate diary format; it is not a full
backup/restore mechanism for AI components.

## One-time server setup

The download includes source, **not a running hosted AI service**. Use Node.js 22 or later
on your Mac or an existing server. The proxy has no npm dependencies.

```sh
cd Recomp/Server
./setup.sh
npm start
```

`setup.sh` asks for your API key without echoing it, generates a random server access token,
and writes a mode-600 `.env` file. Existing `.env` files are not overwritten. **Keep the API
key and token private; never send them in chat or commit `.env`.** Edit the file locally to
read/copy only `RECOMP_ACCESS_TOKEN` into the iPhone app. The OpenAI key remains on the
server. `OPENAI_MODEL` defaults to `gpt-4.1-mini`; use a model that supports image input and
strict Structured Outputs on the Responses API. Access and pricing depend on your API account.

This uses separately billed API requests, not your ChatGPT subscription. Set appropriate
API usage alerts/limits and use a dedicated project key. Each initial estimate and each
refinement is a new request; attached photos are resent so the backend needs no session store.
There is no automatic paid retry. Cancellation attempts to abort in-flight work but cannot
guarantee that a request already accepted by the provider will incur no charge.

### On an iPhone

Put the Node service behind an **HTTPS** endpoint you control, with a valid certificate
trusted by the phone. A standard TLS reverse proxy or an HTTPS-enabled container host works.
Keep access/request-body logging off. Pass `OPENAI_API_KEY` and `RECOMP_ACCESS_TOKEN` as
host environment secrets and do not bake them into the image.

Optional container build on your own host:

```sh
docker build -t recomp-estimator .
docker run --rm --env-file .env -e HOST=0.0.0.0 \
  -p 127.0.0.1:8787:8787 recomp-estimator
```

Have your TLS proxy forward to `127.0.0.1:8787`, allow at least a 12.3 MB JSON request and
an upstream timeout over 70 seconds. Do not expose the unencrypted Node port publicly.

In the iPhone app, open **Settings → Photo & text estimates**:

- Server URL: your HTTPS base address, such as `https://food.your-domain.example`.
  Do **not** append `/v1/estimate`.
- Server access token: the `.env` file’s **RECOMP_ACCESS_TOKEN**, not OPENAI_API_KEY.

Save, then create a food estimate and approve its upload. The app refuses arbitrary HTTP
servers, credentials/query strings embedded in URLs, and HTTP redirects. A per-request
confirmation names the configured server host. Use only a server you trust with the meal.

### In an iOS Simulator

For the initial development check, run Node on your Mac and enter
`http://localhost:8787` in a **Debug simulator** build. Only this combination allows local
HTTP. `localhost` on a real iPhone is the phone, not your Mac; an iPhone needs HTTPS.
Simulator camera capture is unavailable: use a selected photo or text. You can also run
`curl http://127.0.0.1:8787/health` to check the proxy is up; this does not validate its API
key, model access or AI response quality.

The standalone app instructions in README.md still apply: open the Xcode project, keep
the same bundle ID/team when updating an existing installation, and do not delete the app
merely to update it. Updating in place should retain its local diary; export before making
changes. The old 1.0 diary format is covered by a backwards-compatibility unit test.

## Privacy and retention

Before each upload the app lists what will be sent: the selected photos, user-entered food
details, and that meal’s current breakdown. It does **not** read Health data for inference
or send weight, targets, other diary entries, activity or device health history. Anything
you manually type into meal details does become part of the request.

Photos are downsampled/re-rendered to at most 1600 pixels on the longest edge, converted to
JPEG (at most 1.5 MB each) and stripped of original metadata before upload. The photo picker
returns only selected images; broad photo-library permission is not requested. Camera
capture asks for camera permission, never microphone permission, and does not save a new
photo into the photo library. No OCR library is used.

Images are sent only after confirmation. The saved diary can retain up to six resized
photos with the reviewed breakdown; disable Keep photos to save without attachments.
Retained copies are included in encrypted backups, not in Health exports. Originals
remain in Photos. Unsaved drafts and Check scratchpads are not durable across termination. The proxy code neither saves nor logs
request bodies, images, provider responses or credentials; host infrastructure may behave
differently, so review and configure it separately.

Provider requests use **`store: false`**. This disables application response storage, but
**does not mean zero retention**. OpenAI’s current abuse-monitoring/retention policies and
your API project configuration still apply. Images may contain visible personal information
even after metadata removal: photograph the food/label, not faces or unrelated documents.

The server token is stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in Keychain;
it is a revocable password for this proxy. Forgetting app settings deletes the local token,
not the server’s authorization. Rotate the server environment token to revoke it. Keychain
items can survive reinstall; check/forget settings when handing the phone to someone else.

The supplied privacy manifest conservatively declares optional photo, other user content
and health-related meal information processing for app functionality, linked to the user,
with no tracking. This is **not an App Store compliance sign-off**. Verify the deployed
provider/hosting retention, required-reason APIs, policy and App Store privacy labels before
distribution. No HealthKit-sourced records are sent to the AI provider.

## Limits and failure behaviour

This is a **single-user development proxy**, not a public multi-user service. It uses one
random bearer token, a maximum of 6 resized JPEGs, length/number validation, a JSON body limit,
server-side AI timeouts, two concurrent requests maximum, and default global limits of
6 authenticated attempts/minute and 100/day. Counters are in memory and reset on restart;
they are not a durable spending cap. Public distribution requires real per-user authentication,
persistent quotas, HTTPS deployment review and abuse protection. The phone’s access token
must not be reused as a shared embedded token in a publicly distributed app.

An invalid/missing key, denied camera access, network failure, refusal, malformed output,
excessive upload or rate limit leaves the current estimate/diary unchanged. No-food images
can return a question without inventing a meal. Visual estimates and confidence labels are
not validated accuracy measurements and should not be used for medical dosing decisions.

Manual logging, editing an existing item breakdown, and Health sync work without the AI
service. Initial AI estimation/refinement does not work offline. A live API call and real
iPhone camera/Health workflow have **not** been verified in this delivery.

See `Verification/BUILD_STATUS.md` for tests actually run.
