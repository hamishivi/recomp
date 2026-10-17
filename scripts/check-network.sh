#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d); server=''
cleanup() { if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT
# Execute the complete production service and transport. Only the test transport
# reroutes a synthetic HTTPS request to a local fixture; no Keychain or real key.
sources=(); flags=()
if [[ -f Recomp/Services/BoundedHTTPClient.swift ]]; then sources+=(Recomp/Services/BoundedHTTPClient.swift); flags+=(-D RECOMP_BOUNDED_TRANSPORT); fi
if [[ "${RECOMP_NETWORK_ASAN:-0}" == "1" ]]; then flags+=(-sanitize=address); fi
swiftc -swift-version 5 -parse-as-library "${flags[@]}" Recomp/Core/*.swift "${sources[@]}" Recomp/Services/EstimationService.swift TestSupport/NetworkHarness/Harness.swift -o "$work/network"
node TestSupport/NetworkHarness/server.mjs "$work/port" & server=$!
for _ in {1..100}; do [[ -s "$work/port" ]] && break; sleep 0.05; done
[[ -s "$work/port" ]] || { echo 'ERROR: localhost fixture did not start'; exit 2; }
RECOMP_TEST_SERVER="http://127.0.0.1:$(cat "$work/port")" python3 - "$work/network" <<'PYRUN'
import subprocess, sys
try:
    sys.exit(subprocess.run([sys.argv[1]], timeout=60).returncode)
except subprocess.TimeoutExpired:
    print("FAIL: network harness exceeded its 60-second watchdog", flush=True)
    sys.exit(124)
PYRUN
