#!/bin/bash
set -e

echo "==================================="
echo "  Testing Pixi Installation Flow"
echo "==================================="

# Default platform is osx-64 if not provided
PLATFORM=${1:-osx-64}
TEST_DIR="test_pixi_env_$$"

# Ensure clean state
rm -rf "$TEST_DIR"
mkdir "$TEST_DIR"
cd "$TEST_DIR"

echo "[1/4] Initializing pixi project for platform: $PLATFORM"
pixi init --platform "$PLATFORM"
pixi project channel add conda-forge

echo "[2/4] Installing GDAL and build dependencies"
pixi add python gdal rasterio cmake c-compiler cxx-compiler pkg-config make curl

echo "[3/4] Installing gdal-mrsid-builder from source"
# Install the builder package from the parent directory
pixi run pip install ..

echo "[4/4] Running build-mrsid"
pixi run build-mrsid

echo "==================================="
echo "  Pixi Test Passed! Cleaning up..."
echo "==================================="
cd ..
rm -rf "$TEST_DIR"
echo "Done."
