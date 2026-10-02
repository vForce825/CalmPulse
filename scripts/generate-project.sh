#!/bin/bash
set -euo pipefail
# Official pinned XcodeGen, a build-only MIT dependency.
TOOL_DIR="${RUNNER_TEMP:-/tmp}/calmpulse-xcodegen-2.44.1"
if [[ ! -x "$TOOL_DIR/xcodegen/bin/xcodegen" ]]; then
  mkdir -p "$TOOL_DIR"
  curl --fail --location --silent --show-error https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip -o "$TOOL_DIR/xcodegen.zip"
  unzip -q -o "$TOOL_DIR/xcodegen.zip" -d "$TOOL_DIR"
fi
"$TOOL_DIR/xcodegen/bin/xcodegen" generate --spec project.yml
