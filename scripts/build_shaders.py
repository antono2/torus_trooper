#!/usr/bin/env python3
"""Compile and validate every game shader before replacing any output binaries."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent


def shader_tool(name):
    executable = shutil.which(name)
    if executable:
        return executable
    sdk = os.environ.get("VULKAN_SDK")
    if sdk:
        for directory in ("bin", "Bin"):
            executable = shutil.which(name, path=str(Path(sdk) / directory))
            if executable:
                return executable
    raise RuntimeError(f"{name} was not found; install glslang and SPIR-V tools or the Vulkan SDK")


def build_shaders(source_directory, output_directory):
    compiler = shader_tool("glslangValidator")
    validator = shader_tool("spirv-val")
    sources = sorted([*source_directory.glob("*.vert"), *source_directory.glob("*.frag")])
    if not sources:
        raise RuntimeError(f"No shader sources found in {source_directory}")
    with TemporaryDirectory(prefix="torus-shaders-") as temporary:
        binaries = []
        for source in sources:
            binary = Path(temporary) / (source.name + ".spv")
            subprocess.run([compiler, "-V", str(source), "-o", str(binary)], check=True)
            subprocess.run([validator, str(binary)], check=True)
            binaries.append(binary)
        output_directory.mkdir(parents=True, exist_ok=True)
        for binary in binaries:
            shutil.copyfile(binary, output_directory / binary.name)
    print(f"Compiled and validated {len(sources)} shaders")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "shaders")
    args = parser.parse_args()
    try:
        build_shaders(ROOT / "shaders", args.output_dir)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Shader build failed: {error}\n")


if __name__ == "__main__":
    main()
