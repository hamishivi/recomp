#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../.."
python3 scripts/check-interface.py
python3 scripts/check-features.py
python3 scripts/check-dxa-health.py
python3 scripts/check-ui-refresh.py
python3 scripts/check-polish-ui.py
./scripts/check-network.sh
./scripts/check-direct-ai.sh
(cd Server && node --test)
