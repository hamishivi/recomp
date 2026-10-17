# Recomp — install on your iPhone (v1.10.1)

**Start here. This replaces the older server-first setup instructions.**

The normal AI route is now:

> iPhone → OpenAI API → reviewed estimate

You do **not** need Node.js, Docker, a server, Cloudflare, a domain, or a Mac left running to use this route. You need your Mac and Xcode to build/install the app; after installation, AI requests run from your phone over Wi-Fi or mobile data. This is **not offline/on-device AI**. API use is separately billed from ChatGPT. [1]

This download is **unsigned source**, not an `.ipa`, App Store app or TestFlight invitation. Native Xcode compilation, camera/Health/widget behaviour and real-device installation have not been verified in the build environment. Run the native check below before trusting it with your only copy of personal records. See `Verification/BUILD_STATUS.md` for actual test results.

## 1. What you need

- A Mac running an Xcode version that supports your iPhone's installed iOS. The app targets iOS 17 or later.
- Xcode from the Mac App Store, including iOS support and an iPhone Simulator runtime. Open Xcode once and finish its first-launch installation. [2]
- An Apple Account for signing. **The full phone build needs provisioning that supports HealthKit and App Groups.** Capability access depends on membership. A free Personal Team has restrictions and seven-day provisioning; do not assume it supports this complete app. Use an appropriately enrolled development team when Xcode cannot provision these capabilities. Test the simulator build before enrolling just for this app. [3]
- For optional AI: your **own** OpenAI API account with billing, access to GPT-4.1 mini or GPT-4.1, and a dedicated project key. A ChatGPT subscription does not supply API credit. Manual tracking needs no API key. [1,4]

No Apple Intelligence hardware requirement is added. The AI is an HTTPS API request, not a Foundation Models or local-model feature.

## 2. Unzip and prepare the project on your Mac

Unzip **`Recomp-Polish-v1.10.1.zip`**. The enclosed `Recomp` folder contains this `setup.md`, `Recomp.xcodeproj`, the source, and `scripts/`.

**Updating an existing installation?** First make a verified encrypted backup, retain your original DEXA PDFs, and note the existing app bundle identifier, App Group and team. Use those **same** identifiers below. Install over the app; **do not uninstall**. Changing the app's bundle ID creates a different app/diary.

Open Terminal and enter the actual extracted folder. The following assumes it is directly in Downloads:

```bash
cd ~/Downloads/Recomp
```

A reliable alternative is to type `cd `, drag the extracted **Recomp** folder from Finder into Terminal, and press Return. `ls` should show `Recomp.xcodeproj` and `setup.md`.

For a **new installation**, configure a unique set of identifiers, using your own name. These examples are not pre-registered:

```bash
python3 scripts/make_project.py \
  --bundle-id com.hamishiv.recomp \
  --app-group group.com.hamishiv.recomp

open Recomp.xcodeproj
```

For an **update**, substitute the bundle ID and App Group of the installed app. The script regenerates the app, widget and tests consistently. It resets generated signing settings, so choose your team in Xcode afterward. It does **not** register identifiers or groups with Apple.

If `python3` is missing, install Python 3 using its [official macOS installer](https://www.python.org/downloads/macos/), then reopen Terminal. No Python packages are needed.

## 3. Check the native build before using real data

In Xcode, select the **Recomp** scheme and an **iPhone simulator** as the run destination, then choose **Product → Run**. Install a simulator runtime if prompted. Do not choose “Any iOS Device” when you intend to launch a simulator. [2]

For the supplied automated native test gate, run in Terminal from the project folder:

```bash
./scripts/check-native.sh
```

This requires full Xcode and an installed iOS Simulator runtime. It creates its own disposable simulator, tests native backup encryption and the core/UI tests, and builds the app and widget in Release. It saves results under `.native-results/`. It does not install on your personal iPhone or connect to your personal Health store. It has **not** been run successfully in this delivery environment because Xcode is unavailable here.

If the command reports that command-line tools are selected instead of full Xcode, select Xcode in **Xcode → Settings → Locations → Command Line Tools**, or, when Xcode is in the standard location:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

If compilation fails, stop and fix the **first compiler error**, including its filename/line. Do not treat a successful portable Swift test as a successful iPhone build. You do not need Node.js for this native gate or normal app use. Node 22+ is needed only to run the full developer suite's fake-server tests or the optional proxy.

Use synthetic/sample records only in the disposable simulator, never in your real Apple Health.

## 4. Sign and install on your iPhone

### Configure the two targets

In **Xcode → Settings → Apple Accounts** (called Accounts in some versions), sign in with your Apple Account. Select the blue **Recomp** project in the left navigator.

In **TARGETS → Recomp → Signing & Capabilities**:

1. Turn on **Automatically manage signing** and choose your development team.
2. Verify the main bundle identifier, e.g. `com.hamishiv.recomp`.
3. Keep **HealthKit** enabled.
4. Under **App Groups**, register/select your group, e.g. `group.com.hamishiv.recomp`.

Repeat in **TARGETS → RecompWidget → Signing & Capabilities**:

1. Select the **same team** and automatic signing.
2. Verify the widget bundle identifier is the main identifier plus `.widget`.
3. Select the **same App Group**. The widget does not need HealthKit.

Xcode can register eligible resources with your team; the source generator alone cannot. Resolve red signing/provisioning errors here. If Personal Team cannot provision HealthKit/App Groups, use a team with the required capabilities. Do not delete entitlements merely to silence the error and then assume Health/widgets will work. [2,3,5]

### Connect and run

Connect the iPhone by cable, unlock it, and accept **Trust This Computer**. Pair it in Xcode's **Window → Devices and Simulators** if needed. [2]

Enable **iPhone Settings → Privacy & Security → Developer Mode**, restart and confirm. The option may appear only after Xcode starts pairing. [6]

Choose the **Recomp** scheme and **your iPhone** in Xcode's top destination picker, then press **Run ▶**. Accept development/trust prompts and keep the phone unlocked for first launch. Once it has installed and launched successfully, open Recomp from its Home Screen icon. You can disconnect the cable and close Xcode. [2]

A development-signed installation is not permanent distribution: it may eventually need re-signing. Free Personal Team profiles expire after seven days. Rebuild/install over the same app rather than deleting it. A TestFlight/App Store release is not included. [3]

## 5. Enable AI on the phone — no server

### Create a dedicated API key

In the [OpenAI API platform](https://platform.openai.com/), use your own account, create a project for Recomp, configure API billing, and create a personal project key. Use a **Restricted** key with only the permissions needed to create Responses (`POST /v1/responses`); do not use an organization administration key. Make sure your project allows the model you select. [4]

Set a modest spend limit and alerts in the platform. **Check that enforcement is enabled if you expect requests to stop at the limit**; a notification-only budget is not a hard cap. The current spend-limit guide describes the settings and enforcement caveats. The app itself does not enforce an account-wide monetary limit. [7]

Keep the key in a password manager. Enter it privately in Recomp on your phone. **Never paste it into chat, a bug report, source code, `Info.plist`, a screenshot or the ZIP.** There is no `.env` file to create for direct mode.

**Security trade-off:** OpenAI recommends keeping API keys on a backend rather than in mobile apps. Direct mode deliberately lets you supply your own key for this privately installed app. It stores the credential in device-only, when-unlocked Keychain storage, not the diary, widget, or encrypted diary backup. That reduces at-rest exposure but does not make the key safe against a compromised device/app. Do not ship a shared developer key or describe this as a production secret-management solution. The optional server route remains available. [8,9]

### Save and test it

On the iPhone, open **Recomp → Settings → Photo & text estimates**:

1. Set **AI connection → Direct · personal API key**. New setups default to Direct; existing server setups keep Server until you change it.
2. Paste your own **OpenAI API key** into the secure field.
3. Leave **GPT-4.1 mini · lower cost** selected initially. **GPT-4.1 · higher cost** is also supported. The key must have access to the chosen model. [10]
4. Read and enable **I understand the personal-key risk and separate API charges**.
5. Tap **Test connection…** and approve the small billed test. It sends the synthetic text “One large egg, no added oil”, not your diary or any photo. A valid response verifies connectivity, not nutrition accuracy. No food is logged, and there is no automatic retry.
6. Tap **Save** after the test succeeds. Testing alone does not save settings.

Now try **Today → Check food**. Enter a food name, details or food/label photos, choose **Estimate nutrition**, and approve the upload. Review the result, make a manual correction, then try a text refinement. Close the check: nothing should have appeared in your diary. Logging requires the separate **Log this food… → Save** action.

Up to six photos can be used together. Plate, packaging and label images are evidence about the meal, not automatically separate servings. Label reading, portion estimation and refinement can still be wrong: review the values.

### What “no server” does and does not mean

- There is no **server for you to host**. Your phone connects to the fixed `https://api.openai.com/v1/responses` endpoint. AI still needs internet and may incur charges for every estimate, refinement and connection test, including some requests you cancel after the provider accepts them.
- Only approved meal content is uploaded. The request builder has no access to Health, DEXA, exercise history, body measurements or other diary entries. Anything you manually type into meal details is included.
- Photos are resized/re-encoded before upload. Requests use `store: false`, but this is **not a promise of zero retention**; provider abuse-monitoring and other data policies still apply. [11]
- No barcode database, web search or general chatbot is added. Direct mode does not support Azure, arbitrary gateways or region-specific API endpoints.
- You can use the phone while travelling without leaving your Mac awake. The API must be accessible from your current network/region. Offline, existing records and manual entry still work; the app does not silently queue a paid request for later.
- **Forget AI settings** removes the local credential; it does not revoke the key remotely. Revoke an exposed/lost key in the API platform. Keychain items can survive reinstall, so check settings before handing the phone to someone else. Saving the other connection mode removes the inactive credential from this Keychain item; keep your keys separately.

### Coming from the old server setup

Select Direct, enter your API key, test and save. No server redeployment is needed. The legacy server token is not an OpenAI key and cannot be used for direct mode. After confirming Direct works, you can stop your old Node process/tunnel or hosted service. Revoke unused server tokens/keys separately; switching the app does not stop a hosted service or its billing.

Prefer keeping the key off the phone? Select **My server · advanced**, then follow `PHOTO-SETUP.md`. The server source is unchanged from 1.8; it is optional, not part of the main setup above.

## Food logging in v1.10.1

**Today → Log food** is the single entry form. Enter a name, choose **Your usuals**, attach up to six photos, or enter nutrition directly. Photos never require an AI request just to attach them.

- **Estimate nutrition** reads your approved photos/details and fills the same form. **Update estimate** uses additional corrections. API charges still apply.
- Review the totals. **Breakdown** contains individual foods and locks. Tap a food for its values and sources. Typed total changes replace stale ingredients with one protected total. Unlock it before asking AI to change those numbers.
- **Half** and **Double** scale the ingredients together; the toolbar **Undo** restores the preceding food edit. Photo attachments, the meal time and notes are not part of nutrition Undo.
- Check the meal, date and timezone, then **Save**. Nothing is logged before saving. Existing entries keep their IDs when edited.
- **Check food** stays unlogged. Choose **Log this food…**, then **Save**, only when you want an entry.
- **More options → Save as a usual** creates a reusable food shortcut when you save. **Settings → Your usuals** manages saved foods. Swipe to remove a shortcut; logged meals are unaffected.

The compact home summary places rings beside the figures when they fit and stacks them on narrow screens or with larger text. It has four rings: calories, protein, carbs and fat, from outside in. Rings stop at 100%; the figures show actual totals and over-target amounts. A missing/zero target has no progress ring. System appearance, larger text, VoiceOver labels and Reduce Motion are supported in source and need native testing.

## 6. Connect the other features

**Health permissions:** Enable only what you intend to share. Connecting can queue existing local records for export, so start with genuine records only.

| Feature | On-phone setup |
|---|---|
| Food calories/macros | **Settings → Apple Health → Connect Apple Health**. Review read/write permissions. |
| Weight, body fat and waist | **Body → Apple Health measurements → Connect measurements**. Pick the Home/Girlfriend's scale tag when logging. |
| DEXA | **Body → DEXA scans**; import or enter, review and save. Open a scan → **Review Health sharing** and approve its compatible whole-body values/date. |
| Strava and Strong | First enable each app's Apple Health sharing. Then **Settings → Activity & notes** in Recomp, grant read permissions and refresh. This reads summaries, not Strong exercise/rep/set logs. [12] |
| Widget | Give both Xcode targets the same registered App Group. In Recomp **Settings → Home Screen widget**, opt in to showing numbers. Long-press the iPhone Home Screen → **Edit → Add Widget → Recomp**. Its numbers are local-diary-only. |
| Backup | **Settings → Backup & restore**. Save a `.recompbackup` file separately in Files, and keep the password in a password manager. Backups are manual, not automatic iCloud sync. Verify using a separate test diary before relying on restore; do not uninstall your only copy to test it. |
| Travel | Entries retain their selected timezone. After a flight, use **Today → Travel & food coverage** to review the actual interval. See `TRAVEL-1.8.md`; missing intake is never assumed to be fasting. |

In Strava, look for **Settings → Manage Apps and Devices → Health → Send to Health**. In Strong, use **Profile → Settings → App Integrations → Apple Health → Connect**. Menu labels can vary by release. [12]

All this uses on-device permissions, not your ChatGPT connected accounts. Allowing a permission prompt to finish does not guarantee that every permission was granted. Health refresh runs in the foreground/on manual refresh, not as a continuously running sync daemon.

## 7. Troubleshooting and updating

For the signed-widget copy warning, unused `withUnsafeMutableBytes` result, document-opening policy, and simulator startup diagnosis, see **`STARTUP-1.9.1.md`**. That is historical documentation; use the current v1.10.1 patch for a v1.10 installation. Those warnings do not themselves establish a failed build.


| Symptom | What to check |
|---|---|
| Xcode cannot sign or register the App Group | Same team on **both** targets; unique app IDs; group is registered and selected on both; team supports required capabilities. |
| iPhone is unavailable in Xcode | Unlock/trust/pair it, enable Developer Mode, and use an Xcode version with support for its iOS. |
| “OpenAI rejected the API key” | Check the full key, its project and whether it expired/was revoked. Replace it in the app, not in source. |
| API quota/rate limit | Check **API** billing, spend-limit enforcement, remaining credit, and project/model access. ChatGPT billing is unrelated. Do not repeatedly tap retries. |
| API denies request/model | Check model permissions and availability from your current region. Try the other supported model only after confirming access; no automatic fallback occurs. |
| Incomplete/invalid AI output | Keep the draft, simplify the meal or use fewer/clearer images; manual editing works without another paid call. |
| Offline or timeout | Try a functioning internet connection. The draft is unchanged. A cancelled or timed-out request can still be billable if accepted upstream. |
| Secure settings cannot be read | Unlock and retry. Save is disabled after a failed Keychain load, to avoid overwriting an unreadable existing credential. |
| Widget blank | Numbers are off by default. Verify App Group signing, open the app, and allow for iOS-controlled refresh timing. |
| Restored backup has no AI setup | API/server credentials are intentionally not in diary backups. Re-enter them. A credential already in this device's Keychain can remain; inspect before use. |

For future updates, retain a verified backup and original reports; keep the same bundle ID, App Group and development team; Run the newer project over the existing installation. **v1.10.1 retains diary schema 7** and does not change the maintenance calculation or Health sync algorithm. A version earlier than 1.8 cannot read schema 7.

## References

Official references checked September 18, 2026. These describe platform behaviour, not proof that this particular source project has passed native testing.

[1] [ChatGPT and API billing are separate](https://help.openai.com/en/articles/9039756-billing-settings-in-chatgpt-vs-platform).

[2] [Apple: running on simulated and physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

[3] [Apple developer accounts and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account); [supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

[4] [OpenAI projects, model permissions and restricted API keys](https://help.openai.com/en/articles/9186755-managing-your-work-in-the-api-platform-with-projects).

[5] [Apple: enabling app capabilities and App Groups](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).

[6] [Apple: Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

[7] [OpenAI: spend limits, enforcement and caveats](https://developers.openai.com/api/docs/guides/spend-limits).

[8] [OpenAI API-key safety guidance](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety).

[9] [Apple: device-only, when-unlocked Keychain access](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).

[10] [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini); [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1); [image input](https://developers.openai.com/api/docs/guides/images-vision); [structured output](https://developers.openai.com/api/docs/guides/structured-outputs).

[11] [OpenAI API data controls/retention](https://developers.openai.com/api/docs/guides/your-data).

[12] [Strava and Apple Health](https://support.strava.com/hc/en-us/articles/216917527-Health-App-and-Strava); [Strong and Apple Health](https://help.strongapp.io/article/147-sync-with-apple-health).
