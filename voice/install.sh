#!/usr/bin/env bash
# install_spank.sh
# Installs taigrr/spank and registers it as a launchd daemon (sudo spank --sexy)
# Requirements: macOS Apple Silicon (M2+)
# Usage: sudo ./install_spank.sh

set -eo pipefail

PLIST="/Library/LaunchDaemons/com.taigrr.spank.plist"
BIN="/opt/homebrew/bin/spank"


# ── 0. Require sudo ───────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  echo "❌  Please run with sudo: sudo ./install_spank.sh"
  exit 1
fi

# Preserve the calling user's HOME and PATH so go/brew resolve correctly
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
export HOME="$REAL_HOME"
export PATH="$REAL_HOME/go/bin:/usr/local/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── 1. Check platform ────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌  This script is macOS-only." && exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "❌  spank requires Apple Silicon (M2+)." && exit 1
fi

# ── 2. Install Go if missing ──────────────────────────────────────────────────
if ! command -v go &>/dev/null; then
  echo "⚙️   Go not found — installing via Homebrew…"

  if ! command -v brew &>/dev/null; then
    echo "📥  Homebrew not found — installing…"
    sudo -u "$REAL_USER" /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    export PATH="/opt/homebrew/bin:$PATH"
  fi

  sudo -u "$REAL_USER" env PATH="$PATH" brew install go
  export PATH="/opt/homebrew/bin:$PATH"
  echo "✅  Go installed: $(go version)"
else
  echo "✅  Go found: $(go version)"
fi

# ── 3. Build & install spank ──────────────────────────────────────────────────
echo "📦  Installing spank via go install…"
# Run go install as the real user so GOPATH is set correctly
su - "$REAL_USER" -c "env HOME='$REAL_HOME' PATH='$PATH' go install github.com/taigrr/spank@latest"

GOBIN_PATH=$(su - "$REAL_USER" -c "env HOME='$REAL_HOME' PATH='$PATH' go env GOPATH")/bin/spank

if [[ ! -f "$GOBIN_PATH" ]]; then
  echo "❌  Build succeeded but binary not found at $GOBIN_PATH"
  exit 1
fi

mkdir -p "$(dirname "$BIN")"
cp "$GOBIN_PATH" "$BIN"
chmod +x "$BIN"
echo "✅  Binary installed at $BIN"

# ── 4. Unload existing service if present ────────────────────────────────────
if [[ -f "$PLIST" ]]; then
  echo "⚠️   Existing plist found — unloading…"
  launchctl unload "$PLIST" 2>/dev/null || true
fi

# ── 5. Write launchd plist (sexy mode) ───────────────────────────────────────
echo "📝  Writing launchd plist…"
tee "$PLIST" > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.taigrr.spank</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>sleep 60 && /opt/homebrew/bin/spank --sexy</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/spank.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/spank.err</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST"
chown root:wheel "$PLIST"

# ── 6. Load & start the service ───────────────────────────────────────────────
echo "🚀  Loading service…"
launchctl load "$PLIST"

echo "✅  launchd daemon!"
# echo ""
# echo "✅  spank is running in sexy mode as a launchd daemon!"
# echo ""
# echo "Useful commands:"
# echo "  View logs:      tail -f /tmp/spank.log"
# echo "  View errors:    tail -f /tmp/spank.err"
# echo "  Stop service:   sudo launchctl unload $PLIST"
# echo "  Start service:  sudo launchctl load $PLIST"
# echo "  Uninstall:      sudo launchctl unload $PLIST && sudo rm $PLIST $BIN"
