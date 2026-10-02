#!/bin/bash
set -euo pipefail
python3 scripts/audit-source.py
python3 -m unittest discover -s Tests -p 'test_*.py'
swift test --package-path Packages/WellnessCore
swift test
bash scripts/verify-platform.sh
bash scripts/generate-project.sh
xcodebuild -derivedDataPath /tmp/CalmPulseBuild -project CalmPulse.xcodeproj -scheme CalmPulse-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -derivedDataPath /tmp/CalmPulseBuild -project CalmPulse.xcodeproj -scheme CalmPulse-Watch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
bash scripts/test-simulators.sh
bash scripts/capture-watch.sh
