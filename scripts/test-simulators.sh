#!/bin/bash
set -euo pipefail
# Select discovered SDK27 device identifiers, never assume marketing names.
xcrun simctl list devices available -j > /tmp/calmpulse-devices.json
IOS_ID=$(python3 - <<'PY'
import json
for runtime, devices in json.load(open('/tmp/calmpulse-devices.json'))['devices'].items():
    if 'iOS-27-' in runtime:
        for device in devices:
            if device.get('isAvailable') and 'iPhone' in device['name']:
                print(device['udid']); raise SystemExit
raise SystemExit('No available iPhone iOS27 simulator')
PY
)
xcodebuild -project CalmPulse.xcodeproj -scheme CalmPulse-iOS -destination "platform=iOS Simulator,id=$IOS_ID" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
