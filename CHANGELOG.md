# Changelog

## Unreleased

- Keep menu/replay fades and game-over delays consistent across display frame
  rates, including after a slow frame.
- Clarify gameplay tuning and renderer values, separate runtime responsibilities,
  and check project compiler diagnostics during verification.
- Build release archives with freshly compiled and validated shaders.

## 0.23.0

Initial release for Windows and Linux.

- Tunnel racing and shooting with Normal, Hard and Extreme difficulties,
  unlockable starting levels, high scores, charged shots and score multipliers.
- Keyboard, gamepad and joystick controls with configurable bindings, pause,
  menu navigation and suspended-run resume.
- Replay library with recording time, score and duration, custom names,
  sorting, playback in the original player view, and `.ttr` file import/export.
- Vulkan graphics with procedural spacecraft, contrasting hull markings and
  projectile edges, smooth tunnel movement, and an animated title screen.
- Adjustable anti-aliasing, panel/wire/border draw distances, shot distance,
  near-camera blur and fade, rear-track blending, and frame-rate limits.
- Music and sound effects, volume previews, and persistent settings and scores.
- Windows and Linux downloads containing game assets and license notices;
  the Linux archive includes GLFW, the Vulkan loader and X11 support libraries.
- Source-build helpers, model tuning tools, diagnostic overlays and an optional
  OpenCL backend with deterministic CPU verification and fallback.
