#!/bin/bash
set -e

echo "==================================="
echo "  Testing Conda Installation Flow"
echo "==================================="

SUBDIR=${1:-osx-64}
LOCAL_CHANNEL_PATH=${2:-"$(pwd)/tests/test_output/local_channel"}
ENV_NAME="test_mrsid_env_$$"

# Setup Conda environment variables if needed
if [ -z "$CONDA_EXE" ]; then
    echo "[ERROR] Conda not found. Please ensure Conda is installed and activated."
    exit 1
fi

echo "[1/4] Creating conda environment for platform: $SUBDIR"
export CONDA_SUBDIR="$SUBDIR"
conda create -n "$ENV_NAME" python=3.10 gdal-mrsid-builder -c "file://$LOCAL_CHANNEL_PATH" -c conda-forge -y

echo "[2/4] Activating environment"
# To activate conda in bash script reliably
source "$(dirname "$CONDA_EXE")/../etc/profile.d/conda.sh" || true
conda activate "$ENV_NAME"

echo "[3/4] Running build-mrsid"
build-mrsid

echo "[4/4] Verifying gdalinfo output"
gdalinfo --formats | grep -i mrsid

echo "==================================="
echo "  Conda Test Passed! Cleaning up..."
echo "==================================="
conda deactivate
conda env remove -n "$ENV_NAME" -y
echo "Done."
