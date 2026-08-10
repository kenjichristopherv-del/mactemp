#!/bin/bash
# Build the sensor binary and symlink the plugin into SwiftBar.
# Same deployment shape as claude-usage: the repo is the source of truth,
# SwiftBar just holds a symlink, so edits here go live on the next refresh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.swiftbar")"

"$ROOT/build.sh"

chmod +x "$ROOT/mactemp.30s.sh"
mkdir -p "$PLUGIN_DIR"
ln -sfn "$ROOT/mactemp.30s.sh" "$PLUGIN_DIR/mactemp.30s.sh"
echo "linked $PLUGIN_DIR/mactemp.30s.sh -> $ROOT/mactemp.30s.sh"

# Optional: a `mactemp` you can run from anywhere.
if [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ]; then
  ln -sfn "$ROOT/bin/mactemp" "/opt/homebrew/bin/mactemp"
  echo "linked /opt/homebrew/bin/mactemp"
fi

echo
echo "Done. In SwiftBar: Preferences -> Refresh All, or it appears within 30s."
