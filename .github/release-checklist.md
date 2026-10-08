# Desktop release checklist

The player-facing README is the entry point for downloads, controls and settings.
Build requirements and diagnostics belong in the technical reference.

## Verify the release build

- Validate guide links and source anchors with `python3 scripts/check_guide_links.py`.
- Compile shader sources and validate the compiled SPIR-V distributed in each package.
- Require the complete Linux and Windows CI checks to pass for the exact release commit.
  Linux checks include deterministic/OpenCL runs, keyboard menu/resume and replay UI,
  Vulkan validation and extracted packages with host libraries hidden and on Ubuntu 26.04.
- Inspect default-setting title and gameplay media; use isolated player data, Normal
  difficulty and genuine gameplay without scripted diagnostic events.
- Review normal/charged fire, bright and unfilled tracks, selected menu items and
  keyboard/controller menu return on a hardware Vulkan driver.
- Keep platform claims precise: Windows and Linux are supported; macOS is not an
  official graphical target until hardware testing is available.

## Prepare source and downloads

- Keep source, runtime assets and all required license notices together. Do not commit
  player saves, exported recordings, build outputs or local machine paths.
- Include the reviewed shader binaries and runtime assets in the release tree.
- Use the archives built by the final successful CI run. Download them locally, inspect
  their contents and record the source commit and run URL alongside them.
- Generate `SHA256SUMS` from those exact archives. Verify uploaded release asset digests.
- Keep the release as a draft and point it at the same commit as the verified CI run.
  Release notes should explain extraction, launchers, Vulkan drivers, Linux glibc minimum,
  controls/replays/settings and supported platforms.

## Final review

- Review the release notes, downloads and public-facing README.
- Publish the draft release when ready.
- Tag the verified release commit as part of publishing. Do not move an already
  published release tag to different code.
