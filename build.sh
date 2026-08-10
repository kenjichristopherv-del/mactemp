#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/bin"
swiftc -O "$ROOT/mactemp.swift" -o "$ROOT/bin/mactemp"
echo "built $ROOT/bin/mactemp"
"$ROOT/bin/mactemp"
