#!/usr/bin/env bash
# Runs KENGEKI's automated gameplay tests headless. Usage: tools/run_tests.sh [name-filter]
# Requires a Godot 4.3+ binary on PATH as `godot` (or set GODOT=/path/to/godot).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
KENGEKI_TEST="${1:-}" "$GODOT" --headless --path . --fixed-fps 60 res://tests/gameplay_tests.tscn 2>&1 \
  | grep -v 'mesh_get_surface_count\|Parameter "m" is null' \
  | grep -E 'PASS|FAIL|====|SCRIPT ERROR'
