"""
CLI entry point for gdal-mrsid-builder.

Registered as `build-mrsid` via pyproject.toml [project.scripts].
Locates and executes the bundled build_script.sh.
"""

import os
import subprocess
import sys
import platform
from pathlib import Path


def check_architecture():
    """Ensure the user is not running natively on Apple Silicon without Rosetta."""
    if sys.platform == "darwin" and platform.machine() == "arm64":
        print("========================================================")
        print(" [ERROR] Apple Silicon (arm64) native environment detected!")
        print("========================================================")
        print("Extensis MrSID SDK does not provide a native ARM version.")
        print("To use this plugin, your Pixi environment must be configured")
        print("to run under Rosetta 2 (x86_64).")
        print("")
        print("How to fix this:")
        print("  1. Delete your current environment:  rm -rf .pixi")
        print("  2. Open pixi.toml and change platforms to:")
        print("     platforms = [\"osx-64\", \"linux-64\"]")
        print("  3. Run again: pixi run build-mrsid")
        print("========================================================")
        sys.exit(1)


def main():
    """Main entry point: run the MrSID plugin build script."""
    check_architecture()

    # Locate build_script.sh alongside this file
    script_dir = Path(__file__).parent
    build_script = script_dir / "build_script.sh"

    if not build_script.exists():
        print(f"[ERROR] Build script not found: {build_script}", file=sys.stderr)
        sys.exit(1)

    # Determine the environment prefix
    prefix = os.environ.get("CONDA_PREFIX") or os.environ.get("PIXI_ENVIRONMENT_PREFIX")
    if not prefix:
        print(
            "[ERROR] Neither CONDA_PREFIX nor PIXI_ENVIRONMENT_PREFIX is set.\n"
            "       Please run this command inside a pixi or conda environment.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Pass all arguments through to the bash script
    cmd = ["bash", str(build_script)] + sys.argv[1:]

    env = os.environ.copy()
    env["PREFIX"] = prefix

    print(f"[INFO] Environment prefix: {prefix}")
    print(f"[INFO] Running: {' '.join(cmd)}")
    print()

    result = subprocess.run(cmd, env=env)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
