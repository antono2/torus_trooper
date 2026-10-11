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
still includes operating-system components. Software Vulkan provides CI graphics.
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

The published Windows v0.23.0 package fails the unrelated-directory graphical
probe because its shaders use working-directory-relative paths. The source fix
selects assets beside the executable and preserves explicit user file paths.
Rebuilding and publishing a later package is required to deliver this fix to
release-download users; existing release assets are not replaced by these tests.
