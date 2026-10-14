# Compatibility and package validation

[`compatibility.json`](../compatibility.json) records the tested V compiler,
platform bootstrap compilers, module releases, Vulkan headers/Volk, Windows
native build tools and CI software driver. Linux and Windows setup and CI read
these pins. `v.mod` remains the VPM dependency declaration; the resolver rejects
disagreement between its direct dependencies and the compatibility manifest.
The existing dependency checker also verifies the installed transitive graph.

For an upgrade, change the manifest and any affected `v.mod` declaration together.
Run `python3 scripts/test_distribution.py` and
`python3 scripts/compatibility.py --platform linux` (or `--platform windows`).
Require the full application CI, including both package consumers, before
promoting release assets. A passing module build alone is insufficient.

The package consumers download build artifacts onto separate runners. Linux
launches in an Ubuntu 24.04 container with Python, Xvfb and Vulkan runtime tools,
without V, CMake, a C compiler or system GLFW. Windows launches on a separate
hosted VM with a runtime-only PATH and development variables removed; the VM
still includes operating-system components. Because the Windows VM has no GPU
driver installation, the harness stages only `vulkan-1.dll` as the OS Vulkan
runtime in an isolated directory. No SDK headers or other SDK/build DLLs are
available to the application. Software Vulkan provides CI graphics.
These jobs validate packaging, not physical GPU compatibility.

Each consumer extracts and relocates the package into a directory containing
spaces, then launches from an unrelated directory with isolated user settings.
It checks bounded headless simulation, graphical startup and the error exit for
invalid resolution. Linux also checks the simulation checksum and probe output.
Published Windows GUI builds do not provide console output, so their checks use
actual process exit codes. Logs are retained as workflow artifacts.

The **Published desktop package consumers** workflow runs after publication or
manually for a selected release tag. It verifies the archive against that
release's `SHA256SUMS` before extraction. To test locally:

```sh
python3 scripts/test_release_package.py PACKAGE --project torus --checksums SHA256SUMS
```

The Windows v0.23.0 package uses working-directory-relative shader paths and can
fail when launched from an unrelated directory. Upgrade to
[v0.23.1](https://github.com/antono2/torus_trooper/releases/tag/v0.23.1) or later:
that release selects assets beside the executable while preserving explicit user
file paths. Its published Linux and Windows archives passed the
[package-consumer checks](https://github.com/antono2/torus_trooper/actions/runs/38532525783),
including launch from an unrelated directory. The older v0.23.0 assets remain
unchanged; these checks do not modify downloaded packages.

## Diagnose and recover setup

Run `python scripts/doctor.py --v PATH_TO_TESTED_V --modules MODULE_DIRECTORY`
for compiler, tools and installed-release checks. Add `--runtime` to enumerate
Vulkan devices, or `--json` to capture a support report. Diagnostics do not repair
caches or change environment variables. GPU enumeration does not establish video
decode or OpenCL interoperability support.

Windows setup stages new Git checkouts and tool extraction beside the destination,
then commits them only after success. Retry an interrupted download/clone with
the same command. Existing unverified, modified or damaged cache directories are
preserved: choose a fresh `-CacheDirectory` and retain the old one for inspection.
A cached archive with a wrong checksum is identified by path; remove only that
archive after inspecting the failure, then retry. Regression fixtures cover these
failure and recovery paths without downloading real tools.

CI caches vcpkg binary packages by the exact ports commit and compatibility
manifest. vcpkg still validates package ABIs and installs the requested triplets;
compiler upgrades cannot reuse an unchecked installed-directory snapshot.
See [releasing](releasing.md) for collecting and publishing exact tested archives.
