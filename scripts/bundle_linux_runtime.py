#!/usr/bin/env python3
"""Bundle Linux windowing/Vulkan libraries, retaining the system libc and drivers."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


BASE_LIBRARIES = re.compile(r"^(lib(c|m|dl|pthread|rt|resolv|util|nss_[\w]+)\.so|ld-linux)")
# GLFW loads these X11 extensions at runtime, so ldd alone cannot find them.
ROOT_LIBRARIES = (
    "libglfw.so.3", "libvulkan.so.1", "libXrandr.so.2", "libXinerama.so.1",
    "libXcursor.so.1", "libXi.so.6", "libXxf86vm.so.1", "libX11-xcb.so.1",
)


def dependencies(path):
    result = subprocess.run(["ldd", str(path)], capture_output=True, text=True, check=True)
    if "=> not found" in result.stdout:
        raise RuntimeError(f"Missing dependencies for {path}:\n{result.stdout}")
    return re.findall(r"^\s*(\S+) => (/\S+)\s", result.stdout, re.MULTILINE)


def main():
    package, binary = map(Path, sys.argv[1:])
    libraries = package / "lib"
    notices = package / "thirdparty/linux-runtime"
    libraries.mkdir(parents=True)
    notices.mkdir(parents=True)
    cache = subprocess.check_output([shutil.which("ldconfig") or "/sbin/ldconfig", "-p"], text=True)
    available = dict(re.findall(r"^\s*(\S+) \([^\n]*x86-64[^\n]*\) => (/\S+)$", cache, re.MULTILINE))
    pending = dependencies(binary)
    pending.extend((name, available[name]) for name in ROOT_LIBRARIES)
    copied = set()
    manifest = []
    while pending:
        name, source = pending.pop()
        if name in copied or BASE_LIBRARIES.match(name):
            continue
        source = Path(source).resolve()
        owner = subprocess.check_output(["dpkg-query", "-S", str(source)], text=True).splitlines()[0].rsplit(": ", 1)[0]
        metadata = subprocess.check_output([
            "dpkg-query", "-W", "-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}", owner
        ], text=True).split("\t")
        notice = Path("/usr/share/doc") / owner.split(":")[0] / "copyright"
        if not notice.is_file():
            raise RuntimeError(f"License notice missing for {source}: {notice}")
        text = notice.read_text()
        shutil.copyfile(notice, notices / (owner.replace(":", "-") + ".copyright"))
        for common in re.findall(r"/usr/share/common-licenses/([\w.+-]+)", text):
            common_path = Path("/usr/share/common-licenses") / common
            if common_path.is_file():
                shutil.copyfile(common_path, notices / common)
        shutil.copyfile(source, libraries / name)
        copied.add(name)
        manifest.append(dict(library=name, package=metadata[0], version=metadata[1],
                             source_package=metadata[2], source_version=metadata[3],
                             sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
        pending.extend(dependencies(source))
    (notices / "libraries.json").write_text(json.dumps(sorted(manifest, key=lambda row: row["library"]), indent=2) + "\n")
    print(f"Bundled {len(copied)} runtime libraries and their license notices")


if __name__ == "__main__":
    main()
