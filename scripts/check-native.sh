#!/usr/bin/env bash
# Native acceptance gate. Unlike the portable check, missing Xcode is FAILURE,
# never a misleading green skip. Creates/deletes only its own fresh simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'ERROR: native verification requires macOS with full Xcode and an installed iOS Simulator runtime.' >&2
  exit 2
fi
result_root="$(pwd)/.native-results/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$result_root"
simulator=''
cleanup() {
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
xcodebuild -version | tee "$result_root/environment.log"
./scripts/check-backup-mac.sh | tee "$result_root/crypto.log"
./scripts/check-wifi-sync.sh | tee "$result_root/wifi.log"
selection=$(xcrun simctl list -j | python3 -c '
import json,sys
x=json.load(sys.stdin)
r=[r for r in x["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"] and int(r["version"].split(".")[0])>=17]
if not r: sys.exit("Install an iOS 17+ simulator runtime in Xcode Settings.")
r=max(r,key=lambda r:tuple(map(int,r["version"].split("."))))
available=x.get("devices",{}).get(r["identifier"],[])
dev=next((d.get("deviceTypeIdentifier") for d in available if d.get("isAvailable") and "iPhone" in d["name"] and d.get("deviceTypeIdentifier")),None)
if not dev:
    candidates=[d for d in x["devicetypes"] if "iPhone" in d["name"]]
    if not candidates: sys.exit("Install an iPhone simulator device type.")
    dev=candidates[-1]["identifier"]
print(dev+"|"+r["identifier"])
')
simulator=$(xcrun simctl create "Recomp-Audit-$$" "${selection%%|*}" "${selection#*|}")
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
common=(-project Recomp.xcodeproj -scheme Recomp -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath .derivedData-audit CODE_SIGNING_ALLOWED=NO)
xcodebuild "${common[@]}" -configuration Debug -parallel-testing-enabled NO -resultBundlePath "$result_root/Tests.xcresult" test | tee "$result_root/tests.log"
xcodebuild "${common[@]}" -configuration Release build | tee "$result_root/release-build.log"
echo "Native gate passed. Logs, XCTest results and UI screenshots: $result_root"
