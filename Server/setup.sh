#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ -e .env ]]; then
  printf '%s\n' '.env already exists; it was not changed. Edit it locally, then run npm start.'
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then echo 'Install Node.js 22 or later first.' >&2; exit 1; fi
if ! command -v openssl >/dev/null 2>&1; then echo 'OpenSSL is required to generate a random access token.' >&2; exit 1; fi
printf '%s' 'OpenAI API key (hidden): '
IFS= read -r -s api_key
printf '\n'
# Keep the value unquoted in dotenv; API keys do not need whitespace or quotes.
if [[ ! "$api_key" =~ ^sk-[A-Za-z0-9_-]+$ ]]; then echo 'That does not look like an OpenAI API key; no file was written.' >&2; exit 1; fi
umask 077
access_token="$(openssl rand -hex 32)"
printf 'OPENAI_API_KEY=%s\nRECOMP_ACCESS_TOKEN=%s\nOPENAI_MODEL=gpt-4.1-mini\nHOST=127.0.0.1\nPORT=8787\n' "$api_key" "$access_token" > .env
chmod 600 .env
unset api_key access_token
printf '%s\n' 'Created private Server/.env. Copy only RECOMP_ACCESS_TOKEN into Recomp settings.' 'Run npm start. A real iPhone requires an HTTPS server address.'
