#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^import Combine$/d' Recomp/Services/DiaryStore.swift > "$work/DiaryStore.swift"
sed '/^import Combine$/d' Recomp/Services/MealEstimatorModel.swift > "$work/MealEstimatorModel.swift"
# Both harnesses supply observation stand-ins; only retain a single definition.
sed '/^protocol ObservableObject:/d; /^@propertyWrapper struct Published/d' TestSupport/EstimatorHarness/Mocks.swift > "$work/EstimatorMocks.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift "$work/DiaryStore.swift" "$work/MealEstimatorModel.swift" \
  TestSupport/StoreHarness/Mocks.swift "$work/EstimatorMocks.swift" TestSupport/AuditHarness/Harness.swift -o "$work/audit"
"$work/audit"
