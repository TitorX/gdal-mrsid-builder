# GDAL MrSID Plugin Builder 🚀

A lightning-fast, automated builder for adding MrSID (`.sid`) support to GDAL and Rasterio using [Pixi](https://pixi.sh/).

## 📖 Background

Many high-resolution remote sensing datasets, most notably the **NAIP (National Agriculture Imagery Program)** imagery, are distributed in the proprietary Extensis MrSID (`.sid`) format. 

However, because the MrSID SDK is proprietary, standard builds of GDAL (and Python libraries that depend on it, like `rasterio`) available through `conda-forge` or `pip` **do not include MrSID support out of the box**. Historically, reading these files required manually building the entirety of GDAL from source — a heavy, time-consuming, and error-prone process.

**This project solves that problem.**

Using Pixi, this tool acts as an automated compiler. It dynamically downloads the proprietary MrSID SDK, fetches the exact driver source code matching your installed GDAL version, and compiles *only* the MrSID plugin, allowing you to get up and running with 3 simple commands.

## 🖥️ Supported Architectures

- **Linux (x86_64)**
- **macOS (Intel / x86_64)**
- **macOS (Apple Silicon / ARM64)**: *Supported via Rosetta 2.* Because Extensis currently does not provide a native ARM SDK for MrSID, this tool will automatically force your GDAL build environment to use the x86_64 architecture on Apple Silicon Macs, running seamlessly through Rosetta 2 translation.

---

## 📦 What is Pixi?

[Pixi](https://pixi.sh/) is a blazing-fast, modern package manager built on top of the conda ecosystem. Think of it as a much faster alternative to `conda` or `mamba`, combined with project management features similar to `npm` or `cargo`. It manages both Python packages and system-level C/C++ dependencies seamlessly in project-isolated environments.

**Install Pixi in one line (Mac/Linux):**
```bash
curl -fsSL https://pixi.sh/install.sh | bash
```

---

## ⚡ Quick Start (For End Users)

You can instantly configure a new project environment with GDAL, Rasterio, and MrSID support using just a few commands. This builder supports both `pixi` and `conda`.

### 🟢 Using Pixi

> [!IMPORTANT]
> **Strict Architecture Requirement**: You **MUST** initialize your project using `osx-64` or `linux-64` platforms. The proprietary MrSID SDK does **not** have an ARM version. 
> 
> If you omit these flags (especially on Apple Silicon / M-Series Macs), `pixi` will default to `osx-arm64` and the plugin compilation will fail with the following explicit error:
> ```
> ========================================================
>  [ERROR] Apple Silicon (arm64) native environment detected!
> ========================================================
> Extensis MrSID SDK does not provide a native ARM version.
> To use this plugin, your Pixi environment must be configured
> to run under Rosetta 2 (x86_64).
> 
> How to fix this:
>   1. Delete your current environment:  rm -rf .pixi
>   2. Open pixi.toml and change platforms to:
>      platforms = ["osx-64", "linux-64"]
>   3. Run again: pixi run build-mrsid
> ========================================================
> ```

```bash
# 1. Initialize a new Pixi project (force x86_64 architecture)
pixi init --platform osx-64 --platform linux-64

# 2. Add the custom channel where this builder is published
# NOTE: Use the direct API channel URL, do NOT include "/channels/" from the web UI URL!
pixi project channel add https://prefix.dev/remote-sensing

# 3. Add the builder (this automatically installs GDAL, Rasterio, and all build tools)
pixi add gdal-mrsid-builder

# 4. Run the automated build script to inject the MrSID plugin
pixi run build-mrsid
```

### 🔵 Using Conda / Mamba

For Conda or Mamba environments, you must similarly ensure the environment is created for the `osx-64` or `linux-64` architecture.

```bash
# 1. Create and activate a new Conda environment
# Note: On Apple Silicon Macs, you MUST prepend CONDA_SUBDIR=osx-64
CONDA_SUBDIR=osx-64 conda create -n gdal_mrsid_env python=3.10
conda activate gdal_mrsid_env

# 2. Install the builder package
conda install -c https://prefix.dev/remote-sensing -c conda-forge gdal-mrsid-builder

# 3. Run the standalone build command
build-mrsid
```

### ✅ Verifying Installation

That's it! The plugin is now built and injected into your local environment. You can immediately start reading `.sid` files:

```bash
# Verify GDAL support (For Conda, omit 'pixi run')
pixi run gdalinfo --formats | grep -i mrsid

# Read NAIP data with Rasterio (For Conda, omit 'pixi run')
pixi run python -c "import rasterio; ds = rasterio.open('naip_image.sid'); print(ds.profile)"
```

## 🛠️ How It Works

Instead of compiling all of GDAL from source (which takes a long time), this script leverages GDAL's dynamic plugin architecture:

1. **Version Detection**: Detects your installed GDAL version from `conda-forge` (e.g., `3.12.3`).
2. **SDK Download**: Automatically downloads and extracts the official Extensis MrSID DSDK for your OS.
3. **Source Fetching**: Downloads only the small handful of C++ driver files needed for the MrSID format directly from the OSGeo GitHub repository matching your exact version tag.
4. **Standalone Compilation**: Uses a custom CMake configuration to compile the `gdal_MrSID` plugin as a dynamically loaded module (`.so` / `.dylib`).
5. **Deployment**: Places the compiled plugin into `$PREFIX/lib/gdalplugins/`, where GDAL and Rasterio automatically discover it.

## 💻 Local Development

If you want to contribute to this script or test it locally:

```bash
# Clone the repository
git clone https://github.com/titorx/gdal-mrsid-builder.git
cd gdal-mrsid-builder

# Install all development dependencies
pixi install

# Run the build script
pixi run build-mrsid

# Force a clean rebuild (if you modify the bash script)
pixi run build-mrsid --clean

# Run tests to verify the plugin loads correctly
pixi run test-gdal
```

## ⚖️ License

The code in this repository is open-source and licensed under the [MIT License](LICENSE). 

**Disclaimer**: This tool automatically downloads the proprietary Extensis MrSID SDK during the build process. By using this tool, you must agree to the Extensis Developer SDK License Agreement. We do not distribute the SDK binaries in this repository.
