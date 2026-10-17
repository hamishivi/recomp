#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'SKIPPED: exact CryptoKit/CommonCrypto/Security implementation requires macOS. No native cryptography test ran.'
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library Recomp/Core/*.swift Recomp/Services/BackupCrypto.swift TestSupport/BackupHarness.swift -o "$work/backup-harness"
"$work/backup-harness"
