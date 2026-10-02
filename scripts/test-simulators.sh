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
xcrun simctl boot "$IOS_ID" 2>/dev/null || true
xcrun simctl bootstatus "$IOS_ID" -b
set +e
xcodebuild -project CalmPulse.xcodeproj -scheme CalmPulse-iOS -destination "platform=iOS Simulator,id=$IOS_ID" -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 -resultBundlePath /tmp/CalmPulseTests.xcresult CODE_SIGNING_ALLOWED=NO test
status=$?
xcrun xcresulttool get test-results summary --path /tmp/CalmPulseTests.xcresult || true
exit "$status"
