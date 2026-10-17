#!/usr/bin/env bash
# Production request builder, parser and transport. Fake provider on loopback only.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d); server=''
cleanup() { if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT
flags=()
if [[ "${RECOMP_DIRECT_ASAN:-0}" == "1" ]]; then flags+=(-sanitize=address); fi
swiftc -swift-version 5 -parse-as-library ${flags[@]+"${flags[@]}"} Recomp/Core/*.swift \
  Recomp/Services/EstimationService.swift Recomp/Services/BoundedHTTPClient.swift \
  TestSupport/DirectAIHarness/Harness.swift -o "$work/direct"
node TestSupport/DirectAIHarness/server.mjs "$work/port" & server=$!
for _ in {1..100}; do [[ -s "$work/port" ]] && break; sleep 0.05; done
[[ -s "$work/port" ]] || { echo 'ERROR: synthetic AI fixture did not start'; exit 2; }
RECOMP_TEST_SERVER="http://127.0.0.1:$(cat "$work/port")" python3 - "$work/direct" <<'PY'
import subprocess, sys
try: sys.exit(subprocess.run([sys.argv[1]],timeout=60).returncode)
except subprocess.TimeoutExpired: print('FAIL: direct AI harness timeout'); sys.exit(124)
PY
