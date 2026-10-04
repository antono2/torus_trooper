#!/usr/bin/env python3
"""Run a game compilation, failing on warnings or notices in project source files.

Diagnostics from dependencies remain visible. Compiler bootstrap commands are
deliberately not wrapped: this check guards the game source we maintain.
"""

from pathlib import Path
import posixpath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
DIAGNOSTIC = re.compile(r"^(.+?):\d+(?::\d+)?:\s*(?:warning|notice):", re.IGNORECASE)
MSVC_DIAGNOSTIC = re.compile(r"^(.+?)\(\d+(?:,\d+)?\)\s*:\s*warning\b", re.IGNORECASE)
OWNED_DIRECTORIES = {"runtime", "sim", "font5x7", "shaders"}
OWNED_ROOT_FILES = {"torus_trooper.v", "torus_trooper_test.v"}


def project_diagnostic(line, root=ROOT):
    line = ANSI_ESCAPE.sub("", line).strip()
    match = DIAGNOSTIC.match(line) or MSVC_DIAGNOSTIC.match(line)
    if not match:
        return False
    root = str(root).replace("\\", "/").rstrip("/")
    path = match[1].replace("\\", "/")
    if not (path.startswith("/") or re.match(r"^[A-Za-z]:/", path)):
        path = root + "/" + path
    path = posixpath.normpath(path)
    # Windows paths are case insensitive; preserve case sensitivity on Unix.
    if re.match(r"^[A-Za-z]:/", root):
        path, root = path.lower(), root.lower()
    if not path.startswith(root + "/"):
        return False
    relative = path[len(root) + 1:]
    return relative in OWNED_ROOT_FILES or relative.split("/", 1)[0] in OWNED_DIRECTORIES


def main():
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        sys.exit("Usage: check_compiler_diagnostics.py -- COMMAND [ARGUMENT ...]")
    found_diagnostic = False
    try:
        with subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, errors="replace") as process:
            for line in process.stdout:
                print(line, end="", flush=True)
                found_diagnostic |= project_diagnostic(line)
            status = process.wait()
    except OSError as error:
        sys.exit(f"Could not start compiler: {error}")
    if status:
        sys.exit(status)
    if found_diagnostic:
        sys.exit("Game compilation produced project warnings or notices; fix them before merging.")


if __name__ == "__main__":
    main()
