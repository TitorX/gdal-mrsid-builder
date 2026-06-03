#!/bin/bash
set -e

echo "==================================="
echo "  Testing Conda Installation Flow"
echo "==================================="

# Default platform is osx-64 if not provided
SUBDIR=${1:-osx-64}
ENV_NAME="test_mrsid_env_$$"

# Setup Conda environment variables if needed
if [ -z "$CONDA_EXE" ]; then
    echo "[ERROR] Conda not found. Please ensure Conda is installed and activated."
    exit 1
fi

echo "[1/4] Creating conda environment for platform: $SUBDIR"
export CONDA_SUBDIR="$SUBDIR"
conda create -n "$ENV_NAME" python=3.10 gdal rasterio cmake c-compiler cxx-compiler pkg-config make curl -c conda-forge -y

echo "[2/4] Activating environment"
# To activate conda in bash script reliably
source "$(dirname "$CONDA_EXE")/../etc/profile.d/conda.sh" || true
conda activate "$ENV_NAME"

echo "[3/4] Installing gdal-mrsid-builder from source"
# Ensure we are in the root of the repository
if [ -f "pyproject.toml" ]; then
    pip install .
elif [ -f "../pyproject.toml" ]; then
    pip install ..
else
    echo "[ERROR] pyproject.toml not found in current or parent directory."
    exit 1
fi

echo "[4/4] Running build-mrsid"
build-mrsid

echo "==================================="
echo "  Conda Test Passed! Cleaning up..."
echo "==================================="
conda deactivate
conda env remove -n "$ENV_NAME" -y
echo "Done."
