#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "Install XcodeGen first." >&2; exit 1; }
xcodegen generate
xcodebuild -project ScreenRoomRemote.xcodeproj -scheme ScreenRoomRemote -configuration Debug -derivedDataPath "$PWD/build" CODE_SIGNING_ALLOWED=NO build
mkdir -p dist
ditto "$PWD/build/Build/Products/Debug/Screen Room Remote.app" "$PWD/dist/ScreenRoomRemote.app"
open -n "$PWD/dist/ScreenRoomRemote.app"
