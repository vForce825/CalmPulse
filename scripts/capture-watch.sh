#!/bin/bash
set -euo pipefail
xcrun simctl list devices available -j > /tmp/calmpulse-watch-devices.json
WATCH_ID=$(python3 - <<'PY'
import json
for runtime,devices in json.load(open('/tmp/calmpulse-watch-devices.json'))['devices'].items():
    if 'watchOS-27-' in runtime:
        for device in devices:
            if device.get('isAvailable'):
                print(device['udid']); raise SystemExit
raise SystemExit('No available watchOS27 device')
PY
)
xcrun simctl boot "$WATCH_ID" 2>/dev/null || true
xcrun simctl bootstatus "$WATCH_ID" -b
APP=/tmp/CalmPulseBuild/Build/Products/Debug-watchsimulator/CalmPulse-Watch.app
test -d "$APP"
xcrun simctl install "$WATCH_ID" "$APP"
for state in steady high stale learning invalid; do
    SIMCTL_CHILD_CALMPULSE_UI_TESTING=1 SIMCTL_CHILD_CALMPULSE_DEMO_STATE="$state" xcrun simctl launch "$WATCH_ID" com.vforce825.calmpulse.watch
    sleep 4
    xcrun simctl io "$WATCH_ID" screenshot "/tmp/calmpulse-watch-$state.png"
    xcrun simctl terminate "$WATCH_ID" com.vforce825.calmpulse.watch
done
SIMCTL_CHILD_CALMPULSE_UI_TESTING=1 SIMCTL_CHILD_CALMPULSE_WIDGET_GALLERY=1 xcrun simctl launch "$WATCH_ID" com.vforce825.calmpulse.watch
sleep 4
xcrun simctl io "$WATCH_ID" screenshot /tmp/calmpulse-watch-gallery.png
python3 - <<'PY'
from pathlib import Path
import base64
for name in ['watch-steady', 'watch-high', 'watch-stale', 'watch-learning', 'watch-invalid', 'watch-gallery']:
    print('CALMPULSE_SCREENSHOT:'+name+':'+base64.b64encode(Path('/tmp/calmpulse-'+name+'.png').read_bytes()).decode())
PY
