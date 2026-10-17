# Recomp estimation proxy

Full setup, device configuration, privacy notes and limits: [../PHOTO-SETUP.md](../PHOTO-SETUP.md).

Node.js 22+. No npm dependencies. `./setup.sh`, then `npm start`.
Keep `.env` private. Run `node --test` for unit and local HTTP tests with a fake provider.

Routes:

- `GET /health`: process liveness only; no AI request or key check.
- `POST /v1/estimate`: bearer-authenticated, JSON only, at most 12.3 MB.

Request fields: `description` (up to 8000 chars), `clarification` (up to 2000; total
context limited to 8000), `images` (0–6 JPEGs with `base64`, optional `role` and `caption`), optional
`currentEstimate`, `lockedItemIDs`, `excludedFoods`. Unknown top-level fields are rejected.
Do not send HealthKit records or the rest of the diary.

Response: `{title, items, assumptions, questions}`. `questions` is either empty or contains one short, highest-impact calorie clarification; a follow-up answer is limited to 160 characters. Each item has a stable string `id`,
`name`, `portion`, `nutrition: {calories, protein, carbs, fat}`, qualitative `confidence`
and an `assumptions` array. The iPhone calculates totals, never trusts an AI-provided total,
and requires review before saving. Errors are `{error: "..."}` with an appropriate status.

One server access token means one user. Do not publish a shared token or expose the API
without HTTPS. In-memory limits reset at restart and are not a durable spending cap.
No provider key, meal data or images are intentionally logged or saved by this code.

Version 1.7 accepts up to six resized JPEGs with optional role/caption and asks for per-food evidence. Deploy this server with the matching app. It does not provide barcode lookup or process activity/Health records.

1.7.1 rejects non-JSON media types, proxy credentials that reuse an upstream API key, and estimates citing absent photos. Upstream response data is capped during streaming, not after buffering. Run `node --test` for 61 current tests; AI responses are mocked.
