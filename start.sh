#!/bin/bash
# Starts Volta OS using the most recently built executable in build/.
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN=$(ls -t "$DIR"/build/VoltaOS "$DIR"/build/*/VoltaOS 2>/dev/null | head -1)
if [ -z "$BIN" ]; then
    echo "VoltaOS not found: build it first (see README.md)" >&2
    exit 1
fi
export VOLTA_DIR="$DIR"
exec "$BIN" "$@"
