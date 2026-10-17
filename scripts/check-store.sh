#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Compile the production coordinator against clearly labelled test doubles.
# This checks its Swift typing/control flow, not Apple's frameworks or permissions.
sed '/^import Combine$/d' Recomp/Services/DiaryStore.swift > "$work/DiaryStore.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift \
  "$work/DiaryStore.swift" TestSupport/StoreHarness/Mocks.swift TestSupport/StoreHarness/Harness.swift \
  -o "$work/store-harness"
"$work/store-harness"
