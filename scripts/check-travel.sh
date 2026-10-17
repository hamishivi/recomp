#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^import Combine$/d' Recomp/Services/DiaryStore.swift > "$work/DiaryStore.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift "$work/DiaryStore.swift" \
  TestSupport/StoreHarness/Mocks.swift TestSupport/TravelHarness/Harness.swift -o "$work/travel"
"$work/travel"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift TestSupport/TravelHarness/Replay.swift -o "$work/replay"
TZ=America/Los_Angeles "$work/replay" create "$work/legacy.json"
for zone in Australia/Sydney Australia/Adelaide America/Vancouver America/Toronto Europe/Paris Europe/London; do
  TZ="$zone" "$work/replay" read "$work/legacy.json"
done
