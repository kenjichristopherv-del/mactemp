#!/usr/bin/env bash
# Generate the plugin, link it into SwiftBar, and provide a `mactemp` CLI.
# Same deployment shape as claude-usage: the repo is the source of truth and
# SwiftBar just holds a symlink, so edits go live on the next refresh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.swiftbar")"

"$ROOT/dist.sh"

mkdir -p "$PLUGIN_DIR"
ln -sfn "$ROOT/mactemp.30s.sh" "$PLUGIN_DIR/mactemp.30s.sh"
echo "linked $PLUGIN_DIR/mactemp.30s.sh -> $ROOT/mactemp.30s.sh"

# The plugin compiles its own copy into ~/Library/Caches on first run. This
# separate build exists only so `mactemp` works as a plain command.
"$ROOT/build.sh" >/dev/null
if [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ]; then
  ln -sfn "$ROOT/bin/mactemp" "/opt/homebrew/bin/mactemp"
  echo "linked /opt/homebrew/bin/mactemp"
fi

echo
echo "Done. The plugin appears within 30s; if it does not, quit and reopen"
echo "SwiftBar — it only rescans the plugin folder on launch."
