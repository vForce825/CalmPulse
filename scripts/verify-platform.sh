#!/bin/bash
set -euo pipefail
xcodebuild -version
xcodebuild -showsdks
xcrun simctl list runtimes
for sdk in iphonesimulator watchsimulator; do
  version=$(xcrun --sdk "$sdk" --show-sdk-version)
  [[ "$version" == 27.* ]] || { echo "Required SDK 27 missing: $sdk=$version"; exit 1; }
done
xcrun simctl list runtimes -j > /tmp/calmpulse-runtimes.json
python3 - <<'PY'
import json
r=json.load(open('/tmp/calmpulse-runtimes.json'))['runtimes']
for platform in ['iOS','watchOS']:
    assert any(x['name'].startswith(platform+' 27.') and x.get('isAvailable') for x in r), f'Missing available {platform} 27 runtime; no fallback allowed'
print('iOS 27 and watchOS 27 SDK/runtime gate passed')
PY
