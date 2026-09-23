#!/bin/sh
# Builds SynqApp (ad-hoc signed, so sandbox entitlements apply) and optionally launches it.
# Usage: scripts/build.sh [--run]
set -e
cd "$(dirname "$0")/.."
DERIVED="${DERIVED_DATA:-build/DerivedData}"
xcodebuild -project synqapp.xcodeproj -scheme synqapp -configuration Debug \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build 2>&1 | grep -E 'error:|warning: .*(synqapp|SynqCore)/|BUILD' | sort -u
APP="$DERIVED/Build/Products/Debug/synqapp.app"
if [ "$1" = "--run" ]; then
  pkill -x synqapp 2>/dev/null && sleep 1 || true
  open "$APP"
fi
