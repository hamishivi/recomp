#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift test -c release
python3 scripts/check-interface.py
python3 scripts/check-dxa-health.py
./scripts/check-store.sh
./scripts/check-estimator.sh
./scripts/check-composer.sh
./scripts/check-polish.sh
./scripts/check-startup.sh
python3 scripts/check-ui-refresh.py
python3 scripts/check-polish-ui.py
./scripts/check-audit.sh
./scripts/check-audit2.sh
./scripts/check-travel.sh
python3 scripts/check-features.py
if command -v node >/dev/null 2>&1; then ./scripts/check-network.sh; ./scripts/check-direct-ai.sh; (cd Server && node --test); else echo "ERROR: Node 22+ required for server tests." >&2; exit 2; fi
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Core tests complete. Native iOS verification requires macOS with Xcode; no iOS build was performed.'
  if [[ "${1:-}" == "--require-native" ]]; then exit 2; fi
  exit 0
fi
./scripts/check-native.sh
