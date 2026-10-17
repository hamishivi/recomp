#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift Recomp/Services/BackupCrypto.swift Recomp/Services/WiFiSyncService.swift TestSupport/WiFiSyncHarness/Harness.swift -o "$work/wifi-harness"
"$work/wifi-harness"
