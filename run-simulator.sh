#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

devices=$(xcrun simctl list devices available)
device=$(printf '%s\n' "$devices" | sed -nE '/iPad/s/.*\(([0-9A-F-]{36})\) \((Booted|Shutdown)\).*/\1 \2/p' | head -n 1)
if [[ -z "$device" ]]; then
    echo "No iPad simulator is installed. Install an iOS Simulator runtime in Xcode." >&2
    exit 1
fi
read -r device_id device_state <<< "$device"

if [[ "$device_state" != Booted ]]; then
    xcrun simctl boot "$device_id"
fi
open -a Simulator --args -CurrentDeviceUDID "$device_id"

xcodebuild \
    -project Colourbug.xcodeproj \
    -scheme Colourbug \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath .context/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "Waiting for the iPad to finish starting. Its first boot may take several minutes."
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" .context/DerivedData/Build/Products/Debug-iphonesimulator/Colourbug.app
xcrun simctl launch "$device_id" com.colourbug.hello
