#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed '/^import Combine$/d' Recomp/Services/MealEstimatorModel.swift > "$work/MealEstimatorModel.swift"
swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift "$work/MealEstimatorModel.swift" TestSupport/EstimatorHarness/*.swift -o "$work/estimator"
"$work/estimator"
