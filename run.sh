#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Xcode's PNG copy step needs a locale that macOS provides.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

case "${1:---ipad}" in
    --ipad)
        mkdir -p .context
        device_id=${COLOURBUG_DEVICE_ID:-}
        if [[ -z "$device_id" ]]; then
            device_list=$(mktemp)
            trap 'rm -f "$device_list"' EXIT
            xcrun devicectl list devices \
                --filter "State == 'available (paired)' AND hardwareProperties.deviceType == 'iPad'" \
                --json-output "$device_list" >/dev/null
            device_id=$(plutil -extract result.devices.0.hardwareProperties.udid raw \
                -o - "$device_list" 2>/dev/null || true)
        fi
        if [[ -z "$device_id" ]]; then
            echo "No paired iPad is available. Connect and unlock an iPad, or run ./run.sh --simulator." >&2
            exit 1
        fi

        xcodebuild \
            -project Colourbug.xcodeproj \
            -scheme Colourbug \
            -configuration Debug \
            -destination "platform=iOS,id=$device_id" \
            -derivedDataPath .context/DerivedDataDevice \
            build

        xcrun devicectl device install app --device "$device_id" \
            .context/DerivedDataDevice/Build/Products/Debug-iphoneos/Colourbug.app
        xcrun devicectl device process launch --terminate-existing \
            --device "$device_id" com.colourbug.hello
        ;;
    --simulator)
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

        echo "Waiting for the iPad simulator to finish starting."
        xcrun simctl bootstatus "$device_id" -b
        xcrun simctl install "$device_id" .context/DerivedData/Build/Products/Debug-iphonesimulator/Colourbug.app
        xcrun simctl launch "$device_id" com.colourbug.hello
        ;;
    *)
        echo "Usage: ./run.sh [--ipad|--simulator]" >&2
        exit 2
        ;;
esac
