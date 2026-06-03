#!/bin/bash
# =============================================================================
# build_script.sh — Build the GDAL MrSID plugin against a pre-installed GDAL
#
# This script:
#   1. Detects the installed GDAL version from gdal-config
#   2. Downloads the MrSID SDK (cached)
#   3. Downloads matching GDAL source files for the MrSID driver
#   4. Compiles the gdal_MrSID plugin as a standalone MODULE library
#   5. Deploys the plugin + SDK libs into the pixi/conda environment
#
# Usage:
#   build-mrsid           # Normal build
#   build-mrsid --clean   # Force a clean rebuild
# =============================================================================
set -e

# --- Handle --clean flag ---
CLEAN_BUILD=false
for arg in "$@"; do
    if [ "$arg" = "--clean" ]; then
        CLEAN_BUILD=true
    fi
done

# --- Determine environment prefix ---
if [ -z "$PREFIX" ]; then
    if [ -n "$CONDA_PREFIX" ]; then
        PREFIX="$CONDA_PREFIX"
    elif [ -n "$PIXI_ENVIRONMENT_PREFIX" ]; then
        PREFIX="$PIXI_ENVIRONMENT_PREFIX"
    else
        echo "[ERROR] PREFIX, CONDA_PREFIX, or PIXI_ENVIRONMENT_PREFIX must be set"
        exit 1
    fi
fi

echo "========================================================"
echo "  GDAL MrSID Plugin Builder"
echo "========================================================"
echo "[INFO] Environment prefix: $PREFIX"

# --- Build working directory ---
BUILD_ROOT="$PREFIX/share/gdal-mrsid-builder/_build"
LOG_DIR="$BUILD_ROOT/logs"

if [ "$CLEAN_BUILD" = true ]; then
    echo "[INFO] --clean flag set, removing previous build artifacts..."
    rm -rf "$BUILD_ROOT/gdal_mrsid_src"
    rm -rf "$BUILD_ROOT/plugin_build"
fi

mkdir -p "$BUILD_ROOT"
mkdir -p "$LOG_DIR"

# --- 1. Detect installed GDAL version ---
echo ""
echo "[STEP 1/7] Detecting installed GDAL version..."

if ! command -v gdal-config &>/dev/null; then
    echo "[ERROR] gdal-config not found. Is GDAL installed in this environment?"
    exit 1
fi

GDAL_VERSION_RAW=$(gdal-config --version)
# Strip any "dev" suffix: "3.8.2dev" → "3.8.2"
GDAL_VERSION=$(echo "$GDAL_VERSION_RAW" | sed 's/dev$//')
GDAL_INCLUDE_DIR=$(gdal-config --cflags | sed 's/-I//')
GDAL_LIB_DIR=$(gdal-config --dep-libs | grep -o '\-L[^ ]*' | head -1 | sed 's/-L//')

# Fallback lib dir
if [ -z "$GDAL_LIB_DIR" ]; then
    GDAL_LIB_DIR="$PREFIX/lib"
fi

echo "[INFO] GDAL version (raw): $GDAL_VERSION_RAW"
echo "[INFO] GDAL version (clean): $GDAL_VERSION"
echo "[INFO] GDAL include dir: $GDAL_INCLUDE_DIR"
echo "[INFO] GDAL lib dir: $GDAL_LIB_DIR"

# --- 2. OS Detection ---
echo ""
echo "[STEP 2/7] Detecting platform..."

OS_TYPE=$(uname -s)
ARCH_TYPE=$(uname -m)

CMAKE_EXTRA_FLAGS=""
if [[ "$OS_TYPE" == "Darwin" ]]; then
    SDK_URL="https://bin.extensis.com/download/developer/MrSID_DSDK-9.5.4.4709-darwin16.universal.clang80.tar.gz"
    LIB_NAME="libltidsdk.dylib"
    PLUGIN_EXT="dylib"
    CPU_COUNT=$(sysctl -n hw.ncpu)

    if [[ "$ARCH_TYPE" == "arm64" ]]; then
        echo "[WARNING] Apple Silicon detected. Forcing x86_64 architecture for MrSID compatibility."
        CMAKE_EXTRA_FLAGS="-DCMAKE_OSX_ARCHITECTURES=x86_64"
    fi
else
    SDK_URL="https://bin.extensis.com/download/developer/MrSID_DSDK-9.5.4.4709-rhel6.x86-64.gcc531.tar.gz"
    LIB_NAME="libltidsdk.so"
    PLUGIN_EXT="so"
    CPU_COUNT=$(nproc)
fi

echo "[INFO] OS: $OS_TYPE, Arch: $ARCH_TYPE"
echo "[INFO] CPU count: $CPU_COUNT"

# --- 3. Download and extract MrSID SDK ---
echo ""
echo "[STEP 3/7] Preparing MrSID SDK..."

SDK_DIR="$BUILD_ROOT/mrsid_sdk"
SDK_ARCHIVE="$BUILD_ROOT/mrsid_sdk.tar.gz"

if [ -f "$SDK_ARCHIVE" ]; then
    echo "[INFO] MrSID SDK archive already cached, skipping download"
else
    echo "[INFO] Downloading MrSID SDK..."
    curl -L "$SDK_URL" -o "$SDK_ARCHIVE"
fi

if [ -d "$SDK_DIR" ]; then
    echo "[INFO] MrSID SDK already extracted"
else
    echo "[INFO] Extracting MrSID SDK..."
    tar -xzf "$SDK_ARCHIVE" -C "$BUILD_ROOT"
    mv "$BUILD_ROOT"/MrSID_DSDK-* "$SDK_DIR"

    # Patch for modern compilers (remove GCC version check)
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        sed -i '' 's/&& __GNUC__ <= 5//g' "$SDK_DIR/Raster_DSDK/include/lt_platform.h"
    else
        sed -i 's/&& __GNUC__ <= 5//g' "$SDK_DIR/Raster_DSDK/include/lt_platform.h"
    fi
    echo "[INFO] Patched lt_platform.h for modern compiler support"
fi

# Locate SDK paths
MRSID_SDK_ROOT="$SDK_DIR/Raster_DSDK"
MRSID_LIB_PATH=$(find "$MRSID_SDK_ROOT/lib" -name "$LIB_NAME" | head -n 1)
MRSID_INCLUDE_DIR="$MRSID_SDK_ROOT/include"
SDK_LIB_DIR="$MRSID_SDK_ROOT/lib"

if [[ -z "$MRSID_LIB_PATH" || ! -d "$MRSID_INCLUDE_DIR" ]]; then
    echo "[ERROR] Could not find MrSID SDK libraries or headers"
    exit 1
fi

echo "[INFO] MrSID library: $MRSID_LIB_PATH"
echo "[INFO] MrSID include: $MRSID_INCLUDE_DIR"

# --- 4. Download GDAL MrSID driver source files ---
echo ""
echo "[STEP 4/7] Preparing GDAL MrSID driver source (v${GDAL_VERSION})..."

SRC_DIR="$BUILD_ROOT/gdal_mrsid_src"

if [ -d "$SRC_DIR" ] && [ -f "$SRC_DIR/mrsiddataset.cpp" ]; then
    echo "[INFO] GDAL MrSID source files already present"
else
    echo "[INFO] Downloading GDAL MrSID driver source files for v${GDAL_VERSION}..."
    mkdir -p "$SRC_DIR"
    GDAL_RAW_URL="https://raw.githubusercontent.com/OSGeo/gdal/v${GDAL_VERSION}/frmts/mrsid"

    for f in mrsiddataset.cpp mrsidstream.cpp mrsidstream.h \
             mrsiddataset_headers_include.h mrsidstream_headers_include.h \
             mrsiddrivercore.h mrsiddrivercore.cpp; do
        echo "  Downloading $f..."
        if ! curl -sfL "$GDAL_RAW_URL/$f" -o "$SRC_DIR/$f"; then
            echo "[WARNING] Failed to download $f from GDAL v${GDAL_VERSION}"
            echo "[WARNING] URL: $GDAL_RAW_URL/$f"
            echo "[HINT] This file might not exist in this GDAL version, continuing..."
        fi
    done
    echo "[INFO] All source files downloaded"
fi

# --- 5. Generate CMakeLists.txt and build ---
echo ""
echo "[STEP 5/7] Configuring and building the plugin..."

PLUGIN_BUILD_DIR="$BUILD_ROOT/plugin_build"
mkdir -p "$PLUGIN_BUILD_DIR"

# Write standalone CMakeLists.txt
cat > "$PLUGIN_BUILD_DIR/CMakeLists.txt" << 'CMAKEOF'
cmake_minimum_required(VERSION 3.16)
project(gdal_mrsid_plugin C CXX)

# ---- MrSID SDK (provided via -DMRSID_ROOT=...) ----
set(MRSID_ROOT "" CACHE PATH "Path to MrSID Raster_DSDK directory")

find_library(MRSID_LIBRARY
    NAMES ltidsdk lti_dsdk
    PATHS "${MRSID_ROOT}/lib"
    NO_DEFAULT_PATH
    REQUIRED
)
find_path(MRSID_INCLUDE_DIR
    NAMES lt_base.h
    PATHS "${MRSID_ROOT}/include"
    NO_DEFAULT_PATH
    REQUIRED
)

# ---- Source directory (provided via -DMRSID_SRC_DIR=...) ----
set(MRSID_SRC_DIR "" CACHE PATH "Path to GDAL MrSID driver source files")

# ---- GDAL (from the conda/pixi environment) ----
set(GDAL_INCLUDE_DIR "" CACHE PATH "GDAL include directory")
set(GDAL_LIBRARY "" CACHE FILEPATH "Path to libgdal")

# ---- GeoTIFF ----
find_package(PkgConfig REQUIRED)
pkg_check_modules(GEOTIFF libgeotiff)

# Fallback: find geotiff manually if pkg-config fails
if(NOT GEOTIFF_FOUND)
    find_path(GEOTIFF_INCLUDE_DIRS
        NAMES geo_normalize.h
        PATHS "${CMAKE_PREFIX_PATH}/include"
    )
    find_library(GEOTIFF_LIBRARIES
        NAMES geotiff geotiff_i
        PATHS "${CMAKE_PREFIX_PATH}/lib"
    )
    if(GEOTIFF_INCLUDE_DIRS AND GEOTIFF_LIBRARIES)
        set(GEOTIFF_FOUND TRUE)
    endif()
endif()

if(NOT GEOTIFF_FOUND)
    message(FATAL_ERROR "libgeotiff not found. Install it via pixi/conda.")
endif()

# ---- Build the plugin as a MODULE library ----
# Gather all downloaded cpp files
file(GLOB MRSID_SOURCES "${MRSID_SRC_DIR}/*.cpp")

add_library(gdal_MrSID MODULE
    ${MRSID_SOURCES}
)

target_include_directories(gdal_MrSID PRIVATE
    "${GDAL_INCLUDE_DIR}"
    "${MRSID_INCLUDE_DIR}"
    "${MRSID_SRC_DIR}"
    ${GEOTIFF_INCLUDE_DIRS}
)

target_link_libraries(gdal_MrSID PRIVATE
    "${GDAL_LIBRARY}"
    "${MRSID_LIBRARY}"
    ${GEOTIFF_LIBRARIES}
)

# No "lib" prefix — GDAL plugin loader expects "gdal_MrSID.dylib" not "libgdal_MrSID.dylib"
set_target_properties(gdal_MrSID PROPERTIES
    PREFIX ""
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/output"
)
CMAKEOF

echo "[INFO] Generated CMakeLists.txt"

# Find the GDAL library file
GDAL_LIBRARY=$(find "$GDAL_LIB_DIR" -name "libgdal.dylib" -o -name "libgdal.so" | head -n 1)
if [ -z "$GDAL_LIBRARY" ]; then
    # Try a broader search
    GDAL_LIBRARY=$(find "$PREFIX/lib" -name "libgdal.dylib" -o -name "libgdal.so" | head -n 1)
fi

if [ -z "$GDAL_LIBRARY" ]; then
    echo "[ERROR] Could not find libgdal shared library"
    exit 1
fi

echo "[INFO] GDAL library: $GDAL_LIBRARY"

# Configure
cd "$PLUGIN_BUILD_DIR"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

cmake . \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DMRSID_ROOT="$MRSID_SDK_ROOT" \
    -DMRSID_SRC_DIR="$SRC_DIR" \
    -DGDAL_INCLUDE_DIR="$GDAL_INCLUDE_DIR" \
    -DGDAL_LIBRARY="$GDAL_LIBRARY" \
    -DCMAKE_IGNORE_PATH="/opt/homebrew;/usr/local" \
    $CMAKE_EXTRA_FLAGS > "$LOG_DIR/cmake_configure.log" 2>&1

echo "[INFO] CMake configuration complete"

# Build
make -j"$CPU_COUNT" > "$LOG_DIR/make_build.log" 2>&1

echo "[INFO] Plugin compiled successfully"

# --- 6. Deploy the plugin and SDK libraries ---
echo ""
echo "[STEP 6/7] Deploying plugin and libraries..."

PLUGIN_DEST_DIR="$PREFIX/lib/gdalplugins"
mkdir -p "$PLUGIN_DEST_DIR"

# Copy the plugin
BUILT_PLUGIN=$(ls "$PLUGIN_BUILD_DIR/output"/gdal_MrSID.* | head -n 1)
if [ -n "$BUILT_PLUGIN" ] && [ -f "$BUILT_PLUGIN" ]; then
    cp "$BUILT_PLUGIN" "$PLUGIN_DEST_DIR/"
    echo "[INFO] Plugin deployed: $PLUGIN_DEST_DIR/$(basename "$BUILT_PLUGIN")"
else
    echo "[ERROR] Built plugin not found in $PLUGIN_BUILD_DIR/output"
    echo "[ERROR] Build log:"
    cat "$LOG_DIR/make_build.log"
    exit 1
fi

# Copy MrSID SDK shared libraries to prefix/lib for runtime loading
echo "[INFO] Copying MrSID SDK libraries to $PREFIX/lib/"
cp "$MRSID_LIB_PATH" "$PREFIX/lib/"

# Copy the versioned symlink target too
find "$SDK_LIB_DIR" -name "libltidsdk.*" ! -type l -exec cp {} "$PREFIX/lib/" \; 2>/dev/null || true

if [[ "$OS_TYPE" == "Darwin" ]]; then
    # Copy companion TBB libraries required by MrSID on macOS
    find "$SDK_LIB_DIR" -name "*tbb*" -exec cp {} "$PREFIX/lib/" \; 2>/dev/null || true

    echo "[INFO] Fixing RPATH for macOS compatibility..."
    install_name_tool -add_rpath "$PREFIX/lib" "$PLUGIN_DEST_DIR/$(basename "$BUILT_PLUGIN")" 2>/dev/null || true

    # Fix RPATH on SDK libraries
    for lib in "$PREFIX/lib"/libltidsdk*; do
        [ -f "$lib" ] && install_name_tool -add_rpath "$PREFIX/lib" "$lib" 2>/dev/null || true
    done
fi

echo "[INFO] Deployment complete"

# --- 7. Verification ---
echo ""
echo "[STEP 7/7] Verifying installation..."
echo ""

VERIFY_OK=true

# Test 1: gdalinfo --formats
if gdalinfo --formats 2>/dev/null | grep -qi "mrsid"; then
    echo "[PASS] gdalinfo --formats reports MrSID support"
else
    echo "[FAIL] gdalinfo --formats does NOT report MrSID support"
    VERIFY_OK=false
fi

# Test 2: read a .sid file with gdalinfo
SID_TEST_FILE="$SDK_DIR/examples/data/meg_cr20.sid"
if [ -f "$SID_TEST_FILE" ]; then
    if gdalinfo "$SID_TEST_FILE" > /dev/null 2>&1; then
        echo "[PASS] gdalinfo can read .sid file: $(basename "$SID_TEST_FILE")"
    else
        echo "[FAIL] gdalinfo cannot read .sid file"
        VERIFY_OK=false
    fi
else
    echo "[SKIP] No .sid test file found at $SID_TEST_FILE"
fi

# Test 3: read with rasterio
if command -v python &>/dev/null && [ -f "$SID_TEST_FILE" ]; then
    if python -c "
import rasterio
with rasterio.open('$SID_TEST_FILE') as ds:
    print(f'  Driver: {ds.driver}')
    print(f'  Size: {ds.width}x{ds.height}')
    print(f'  Bands: {ds.count}')
" 2>/dev/null; then
        echo "[PASS] rasterio can read .sid files"
    else
        echo "[FAIL] rasterio cannot read .sid file"
        VERIFY_OK=false
    fi
else
    echo "[SKIP] Python or test file not available for rasterio test"
fi

echo ""
echo "========================================================"
if [ "$VERIFY_OK" = true ]; then
    echo "  SUCCESS: MrSID plugin built and installed!"
else
    echo "  WARNING: Build completed but some verifications failed."
    echo "  Check logs in: $LOG_DIR"
fi
echo "========================================================"
echo ""
echo "Plugin location: $PLUGIN_DEST_DIR/gdal_MrSID.$PLUGIN_EXT"
echo "SDK libraries:   $PREFIX/lib/$LIB_NAME"
echo ""
