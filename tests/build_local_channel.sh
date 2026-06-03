#!/bin/bash
set -e

echo "==================================="
echo "  Building local Conda channel"
echo "==================================="

CHANNEL_DIR="$(pwd)/tests/test_output/local_channel"
mkdir -p "$CHANNEL_DIR/noarch"
mkdir -p "$CHANNEL_DIR/osx-64"
mkdir -p "$CHANNEL_DIR/linux-64"
mkdir -p "$CHANNEL_DIR/osx-arm64"

echo "[1/3] Running pixi build..."
pixi build

echo "[2/3] Copying built packages to local channel..."
find .pixi/bld -name "*.conda" -exec cp {} "$CHANNEL_DIR/noarch/" \;
find .pixi/bld -name "*.tar.bz2" -exec cp {} "$CHANNEL_DIR/noarch/" \; 2>/dev/null || true

echo "[3/3] Indexing local channel..."
if command -v conda &> /dev/null; then
    # Create the repodata.json required by conda and pixi
    conda index "$CHANNEL_DIR"
else
    echo "[ERROR] conda is required to run conda-index and build the local channel."
    exit 1
fi

echo "==================================="
echo "  Local channel ready at $CHANNEL_DIR"
echo "==================================="
