#!/usr/bin/env python3
"""Package a built Windows executable with its assets and license notices."""

import argparse
import os
from pathlib import Path
import subprocess
from zipfile import ZIP_DEFLATED, ZipFile
from tempfile import TemporaryDirectory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if not args.binary.is_file():
        parser.error(f"Build the game first; executable not found: {args.binary}")
    with args.binary.open("rb") as executable:
        if executable.read(2) != b"MZ":
            parser.error("The executable is not a Windows binary")
    if args.archive.exists():
        parser.error(f"Refusing to overwrite: {args.archive}")
    files = [root / name for name in ("LICENSE", "README.md", "CHANGELOG.md", "TUNING.md")]
    files.append(root / "thirdparty/miniaudio/LICENSE")
    for directory in ("shaders", "sounds", "models", "docs"):
        files.extend(path for path in sorted((root / directory).rglob("*")) if path.is_file() and path.suffix != ".spv")
    with TemporaryDirectory(prefix="torus-package-shaders-") as temporary:
        shader_directory = Path(temporary)
        compiler = os.environ.get("VEXE") or "v"
        subprocess.run([compiler, "run", str(root / "scripts/build_shaders.vsh"),
                        "--output-dir", str(shader_directory)], check=True)
        with ZipFile(args.archive, "x", compression=ZIP_DEFLATED) as archive:
            archive.write(args.binary, "torus-trooper/torus_trooper.exe")
            for path in files:
                archive.write(path, "torus-trooper/" + path.relative_to(root).as_posix())
            for path in sorted(shader_directory.glob("*.spv")):
                archive.write(path, "torus-trooper/shaders/" + path.name)
    print(f"Packaged {args.archive}")


if __name__ == "__main__":
    main()
