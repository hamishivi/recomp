#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^import Combine$/d' Recomp/Services/DiaryStore.swift > "$work/DiaryStore.swift"
sed '/^import Combine$/d' Recomp/Services/MealEstimatorModel.swift > "$work/MealEstimatorModel.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift "$work/DiaryStore.swift" "$work/MealEstimatorModel.swift" \
  TestSupport/StoreHarness/Mocks.swift TestSupport/PolishHarness/Estimation.swift TestSupport/PolishHarness/Harness.swift -o "$work/polish"
"$work/polish"
