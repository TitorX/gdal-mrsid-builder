#!/bin/bash
set -e

echo "==================================="
echo "  Testing Pixi Installation Flow"
echo "==================================="

# Default platform is osx-64 if not provided
PLATFORM=${1:-osx-64}
LOCAL_CHANNEL_PATH=${2:-"$(pwd)/tests/test_output/local_channel"}
TEST_DIR="$(pwd)/tests/test_output/test_pixi_env_$$"

# Ensure clean state
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "[1/4] Initializing pixi project for platform: $PLATFORM"
pixi init --platform "$PLATFORM"
pixi project channel add "file://$LOCAL_CHANNEL_PATH"
pixi project channel add conda-forge

echo "[2/4] Installing gdal-mrsid-builder from local channel"
# This will automatically pull GDAL, Rasterio, Python and build tools!
pixi add gdal-mrsid-builder

echo "[3/4] Running build-mrsid"
# Directly run it!
pixi run build-mrsid

echo "[4/4] Verifying gdalinfo output"
pixi run gdalinfo --formats | grep -i mrsid

echo "==================================="
echo "  Pixi Test Passed! Cleaning up..."
echo "==================================="
cd ../../..
rm -rf "$TEST_DIR"
echo "Done."
