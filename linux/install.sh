#!/bin/bash
# ZedDisplay +SignalK — Linux installer
# Installs runtime dependencies and the app

set -e

echo "Installing ZedDisplay +SignalK dependencies..."
sudo apt-get install -y libgtk-3-0 gstreamer1.0-plugins-good 2>/dev/null || echo "Note: could not install dependencies via apt. You may need to install libgtk-3-0 and gstreamer1.0-plugins-good manually."

INSTALL_DIR="$HOME/.local/share/zed-display"
BIN_LINK="$HOME/.local/bin/zed-display"

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$(dirname "$BIN_LINK")"

# Copy everything from the bundle directory (script's location)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR"/
chmod +x "$INSTALL_DIR/zed_display"

# Create symlink in PATH
ln -sf "$INSTALL_DIR/zed_display" "$BIN_LINK"

echo ""
echo "ZedDisplay installed successfully!"
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
  export PATH="$HOME/.local/bin:$PATH"
  echo "Added ~/.local/bin to PATH (via ~/.profile)"
fi

echo "Run with: zed-display"
