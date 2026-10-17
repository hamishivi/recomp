# Recomp changelog

## 1.10.1 — food-draft fixes and interface refinement

- Complete, bounded nutrition Undo restores values, context, sources and estimated/verified state, including manual totals outside the AI schema. Undo remains available after deleting the last ingredient.
- Preserve ingredients during portion scaling, keep unchanged lock status on editing, refresh numeric fields on same-total replacement, reject stale-photo AI results and invalid attachments/timezones/context.
- Cancellable photo-batch identities prevent superseded loads from committing or clearing newer state. Retain decoded thumbnails across ordinary form updates.
- Compact concentric-ring home summary with adaptive fallbacks; quieter food rows, a thumbnail strip, grouped logging options and Settings submenus. Keep native controls, direct numerical edits, accessibility labels, consent and warnings.
- Build CSVs on demand; allow analysis export when only target or maintenance history exists. No-op existing-meal Save avoids unnecessary diary/Health updates in the view route.
- Add portable core/controller regressions, static UI contracts and native UI tests. Native Xcode/UI execution remains unverified; see Verification/BUILD_STATUS.md.
- Version 1.10.1 / build 15 / diary schema 7. Server, Health adapter, maintenance/travel equations, cryptography and API contracts unchanged.

## 1.10 — unified food entry and rings

Unified manual/photo/AI food entry, concentric intake rings, simpler home layout, borders instead of numbered sections, and saved-food submenu. See UI-1.10.md and historical verification.

## 1.9.1 — startup and build-warning fixes

Reduce repeated diary decoding, comparisons, maintenance calls and widget writes; coalesce startup reads. Preserve signing while applying warning fixes. See STARTUP-1.9.1.md and historical verification.

## 1.9 — direct personal AI and human setup

- Add explicit personal-key direct OpenAI mode, with device-only Keychain credentials, fixed API endpoint, separate billing/risk acknowledgement, per-request consent and a billed synthetic connection test. No hosting required.
- Retain server mode and migrate older Keychain configuration without rerouting it; saving a new mode removes the inactive secret. No diary-schema migration.
- Move the existing food-only prompt/schema and validation to a tested native request recipe, preserving six photos, label evidence, locks and no-log checks. Bounded transport, redirect refusal, cancellation and no automatic retries remain.
- Add setup.md for Xcode/signing/App Groups/iPhone installation, direct AI, Health/workout sharing, backups and travel. Version 1.9, build 12, schema 7.

## 1.8 — travel support

Frozen entry civil dates/timezones, reviewed absolute food coverage, elapsed-time maintenance across countries, retained same-scale comparisons and honest legacy-timezone inference. See TRAVEL-1.8.md.

## 1.7.2 — second bug pass

- Bounded streaming in the actual Swift HTTP client, including decompressed/chunked data, cancellation, denied redirects and an independent overall deadline. Reject wrong response media types and nonexistent photo references. Release unread upstream error bodies in the Node proxy.
- Activity opt-in is persisted before reading; failures do not start reads. Coalesce overlapping refreshes, clear prior connection errors on retry, and include activity in the general Health pause action. Re-evaluate today's maintenance snapshot after removing imported weights.
- Keep unchanged verified meals verified when reopening a breakdown. Persist Gregorian day keys regardless of the device display calendar. Guard invalid/overflowing step counts and derived percentages instead of trapping during integer formatting.
- Add portable regressions and an actual localhost URLSession harness, wired into the normal test gate. Native Xcode/HealthKit/widget/crypto execution remains unverified; see BUG-SWEEP-1.7.2.md.
- Version 1.7.2 / build 10. Diary schema 6; no new permissions, server configuration or App Group changes.

## 1.7.1 — first bug pass

Sync/date races, corrected-photo totals, evidence references, review invalidation, disk-failure handling, persisted-state validation, bounded upstream responses and native test scaffolding. See the retained BUG-SWEEP-1.7.1.md for historical before/after evidence and limitations.

## 1.7 — backups, photo evidence, checks, activity and widgets

Schema 6; backwards decode of schemas 1–5. Native encrypted-backup source and empty-only reviewed restore preserving IDs/receipts, initially paused connections. Up to six retained JPEG attachments, photo roles/captions and AI evidence. Non-saving Check mode with optional manual values. Read-only Health workout summaries, steps/sleep and context notes; Strava/Strong via Health, no exercise sets/reps. Native WidgetKit extension with App Groups, privacy-sensitive local-food snapshot and editor deep links. Existing scale-aware maintenance and Health/DXA rules retained. See latest verification report for tested versus unverified paths.

# 1.5 — DEXA / DXA report ingestion

- Native PDF/text/manual review flow and a separate local scan history, retaining original units and explicit anatomical sites.
- Conservative labelled-value candidates; no table-order guessing, date inference, OCR or AI upload.
- Fat, lean soft tissue, fat-free mass, bone mineral, VAT dimensions and reported RMR stay distinct.
- Optional protected report retention, exact-file duplicate detection, editable same-ID records, scanner-group differences and CSV/PDF exports.
- DXA records do not enter Health export, scale fitting or target adjustment. Existing engine/server/Health adapter unchanged.
- Schema 1–3 migration to 4; 210 portable tests and 61 mocked coordinator checks. Native build remains unverified.

# Changelog

## 1.4 — Instrument-style native interface

- Replaced the old neon/ring/card-heavy presentation with off-white and graphite surfaces, an orange action tint, aligned monospaced readouts and thin rules.
- Kept native TabView/NavigationStack, forms, sheets, date pickers, photo selection and Charts; food diary becomes a continuous ledger and macro totals a single table.
- Added System/Light/Dark appearance, light/dark/increased-contrast colour assets, scalable readouts and an original level-meter icon.
- Added a read-only native interface gallery and Xcode previews. Separately rendered HTML/PNG design references are explicitly not native screenshots.
- All Core, Services and Server source files are unchanged from 1.3; diary remains schema 3. The appearance preference uses app-owned UserDefaults and its required-reason declaration.
- 168 Debug + 168 Release core tests, 47 mocked coordinator checks, 42 mocked-provider server tests and 71 static interface checks passed. Native Xcode/iPhone build and visual behaviour remain unverified.

# 1.3 — Scale/location tags (September 18, 2026)

- Home and Girlfriend’s starter labels; add/rename/archive/restore custom physical scales.
- Optional per-check-in tags, remembered new-entry default, historical edits and local-only imported-sample annotations.
- Separate per-scale charts, rolling averages, filters and CSV labels. No GPS, Health metadata or estimator uploads for tags.
- Within-scale pairwise weight trends with separate nuisance baselines, minimum comparable coverage, conflicting-source guard and single-scale selector.
- Untagged entries stay untagged on schema-1/2-to-3 migration; no invented measurements or calibration.
- Read-only two-scale demo; expanded portable tests and coordinator harness. Native iOS build remains unverified.

# 1.2 — Measurements and adaptive maintenance (2026-09-18)

- Add weight, body-fat percentage and seven tape measurements, timestamps, method/notes, edit/delete, unit conversion and local trend exclusions.
- Add separately opted-in HealthKit body-mass/body-fat/waist read/write code with stable IDs, version receipts, retry/deletion queues and local/import deduplication.
- Require explicit complete-day snapshots for trend-based maintenance. Local food edits invalidate affected confirmations; missing days are never assumed zero.
- Add a deterministic 21–42-day robust weight/intake heuristic, labelled sensitivity ranges and conservative, optional target proposals with review and cooldown.
- Add editable coaching preferences, macro recalculation, target-change and estimate histories, CSV exports and synthetic read-only demo scenarios.
- Migrate schema-1 diaries without inventing measurements or food confirmations. New writes use schema 2; older builds cannot read it.
- Preserve photo/text estimation and refinement; new maintenance features do not call the AI server or upload Health data.
- Add 74 portable core tests and a mocked coordinator harness; retain the existing food/AI/server tests.

# 1.1 — photo and text estimation

- Camera and selected-photo input, up to three images; optional text-only estimation.
- Resizing, orientation normalization and removal of original image metadata.
- Explicit consent before each external AI request, with a visible server destination.
- Editable food components, total calories/macros, visible assumptions and useful questions.
- Text refinements based on the current snapshot; before/change calorie summary and undo.
- Per-item portion multipliers, add/remove, deterministic preservation of locked edits.
- Reopen saved AI breakdowns and update the same diary/Health meal identity.
- Original manual diary, goals, saved foods, CSV export, trends and opt-in Health sync retained.
- Optional/backwards-compatible AI breakdown field; no photos in the diary or Health exports.
- Keychain-stored proxy token; OpenAI API key stays server-side.
- Dependency-free authenticated Node proxy, strict structured output and validation,
  quota/concurrency/input limits, sanitized errors and mocked-provider tests.
- 24 added portable Swift tests (62 total) and 42 Node unit/HTTP tests.

Still an unsigned Xcode source project. Native build, device workflows and live AI inference
are not verified in this environment. No hosting, API credits or App Store distribution included.
