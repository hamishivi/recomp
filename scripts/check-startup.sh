#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^import Combine$/d' Recomp/Services/DiaryStore.swift > "$work/DiaryStore.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift "$work/DiaryStore.swift" \
  TestSupport/StoreHarness/Mocks.swift TestSupport/StartupHarness/Coordinator.swift -o "$work/startup"
"$work/startup"
