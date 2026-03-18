#!/bin/bash
# ZedDisplay +SignalK — macOS installer
# Removes quarantine flag and installs to Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="zed_display.app"
APP_PATH="$SCRIPT_DIR/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_NAME not found in $(dirname "$APP_PATH")"
  echo "Make sure you extracted the zip first."
  exit 1
fi

echo "Removing quarantine flag..."
xattr -cr "$APP_PATH"

echo "Moving to /Applications..."
if [ -d "/Applications/$APP_NAME" ]; then
  echo "Removing previous installation..."
  rm -rf "/Applications/$APP_NAME"
fi
cp -R "$APP_PATH" /Applications/

echo ""
echo "ZedDisplay +SignalK installed successfully!"
echo "Open from Applications or run: open /Applications/$APP_NAME"
