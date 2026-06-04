#!/bin/bash
set -e

echo "=========================================================="
echo "  Starting All End-to-End Tests (Local Channel & Environments)"
echo "=========================================================="

# 1. Build the local channel
./tests/build_local_channel.sh

# Get current platform to pass to tests
OS_TYPE=$(uname -s)
if [[ "$OS_TYPE" == "Darwin" ]]; then
    DEFAULT_PLATFORM="osx-64"
else
    DEFAULT_PLATFORM="linux-64"
fi

echo "Detected OS: $OS_TYPE -> using platform $DEFAULT_PLATFORM for local tests."

# 2. Run Pixi Test
./tests/test_pixi.sh "$DEFAULT_PLATFORM"

# 3. Run Conda Test
./tests/test_conda.sh "$DEFAULT_PLATFORM"

echo "=========================================================="
echo "  🎉 All Tests Passed Successfully!"
echo "=========================================================="
