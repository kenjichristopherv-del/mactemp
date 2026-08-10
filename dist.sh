#!/usr/bin/env bash
# Generate the distributable single-file plugin from mactemp.swift +
# plugin.template.sh. The generated file is committed so the xbar repo gets a
# self-contained plugin, but this is the only place it should be produced.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/mactemp.30s.sh"

AUTHOR="${MACTEMP_AUTHOR:-Kenji Tubera}"
GITHUB="${MACTEMP_GITHUB:-kenjichristopherv-del}"
ABOUTURL="${MACTEMP_ABOUTURL:-https://github.com/$GITHUB/mactemp}"

SRC_HASH="$(shasum -a 256 "$ROOT/mactemp.swift" | cut -c1-12)"

# Sanity: the embedded source must not contain the heredoc terminator.
if grep -q '^SWIFT_SOURCE_EOF$' "$ROOT/mactemp.swift"; then
  echo "error: mactemp.swift contains the heredoc terminator" >&2; exit 1
fi

awk -v src="$ROOT/mactemp.swift" '
  /@SWIFT_SOURCE@/ { while ((getline line < src) > 0) print line; next }
  { print }
' "$ROOT/plugin.template.sh" \
| sed -e "s|@SRC_HASH@|$SRC_HASH|g" \
      -e "s|@AUTHOR@|$AUTHOR|g" \
      -e "s|@GITHUB@|$GITHUB|g" \
      -e "s|@ABOUTURL@|$ABOUTURL|g" > "$OUT"

chmod +x "$OUT"

# The generated plugin must be valid bash and free of unsubstituted markers.
bash -n "$OUT"
if grep -q '@[A-Z_]*@' "$OUT"; then
  echo "error: unsubstituted placeholder in $OUT:" >&2
  grep -n '@[A-Z_]*@' "$OUT" >&2; exit 1
fi

echo "generated $OUT  ($(wc -l < "$OUT" | tr -d ' ') lines, swift hash $SRC_HASH)"
