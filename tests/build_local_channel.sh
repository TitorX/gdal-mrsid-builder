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

echo "[1/2] Building and publishing to local channel..."
pixi publish --target-channel "file://$CHANNEL_DIR"

echo "==================================="
echo "  Local channel ready at $CHANNEL_DIR"
echo "==================================="
