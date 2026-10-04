# Desktop technical reference

[Back to the game](../README.md) · [Design guide](learning-path.md) ·
[Source repository](https://github.com/antono2/torus_trooper)

This reference covers source builds, advanced settings, saved data, model tuning,
and diagnostics. For downloads, gameplay and everyday controls, start with the
[README](../README.md). Build and test commands assume a source checkout with the
repository root as the working directory.

- [Supported platforms](#supported-platforms)
- [Desktop build requirements](#desktop-build-requirements)
- [Build and run](#build-and-run)
- [Advanced settings and controls](#advanced-settings-and-controls)
- [Saved data and replays](#saved-data-and-replays)
- [Development tools and runtime](#development-tools-and-runtime), including the [code and tuning map](code-map.md)
- [Verification](#verification)
- [Packaging](#packaging)
- [License](#license)

## Supported platforms

| Platform | Requirements and launch command |
| --- | --- |
| Windows 10/11 x64 | A Vulkan-capable graphics driver. Extract the ZIP and launch `torus_trooper.exe`. |
| Linux x64 | glibc 2.38 or newer and a Vulkan-capable graphics driver. Extract the archive and run `./play.sh`. |
| macOS | Not officially supported. |

The Linux download includes GLFW, the Vulkan loader and X11 support libraries.
Its launcher selects the bundled libraries and the correct asset directory.
Keep the executable, `shaders/`, `sounds/` and `models/` together. Downloaded
packages do not require a V compiler or development headers.

## Desktop build requirements

The [CI workflow](../.github/workflows/ci.yml) records the tested compiler,
module and native dependency revisions.

| Component | Source-build requirement |
| --- | --- |
| V compiler | The unmodified upstream V3 revision pinned in CI. The Linux helper prepares it automatically. |
| C compiler | GCC on Linux; a Windows x64 MinGW Clang toolchain on Windows. |
| Windowing | GLFW 3 development files; the Windows helper uses the static MinGW library. |
| Vulkan | A Vulkan 1.1 loader and compatible graphics driver, plus development headers at version 1.4.363 or newer and Volk headers. |
| V modules | The tested `antono2.vulkan`, `antono2.vkmemalloc`, `antono2.memory` and `antono2.opencl` revisions pinned in CI and the Linux helper. |
| Optional OpenCL execution | An OpenCL development loader and an installed device runtime. |

The generated Vulkan bindings require newer **headers** than the minimum
loader and driver. Set `VULKAN_SDK` to a compatible Vulkan SDK or Vulkan-Headers
checkout when configuring the toolchain manually.

Audio uses the vendored miniaudio library and needs no separate audio development
package. Audio initialization failures are logged; the game can continue silently.

## Build and run

### Linux

Install `git`, `make`, `gcc`, `libglfw3-dev`, `libvulkan-dev` and
`libvulkan-volk-dev` on Debian or Ubuntu, along with a suitable graphics driver.
Then build and launch:

```sh
bash scripts/build_linux_v3.sh
./torus_trooper
```

The helper downloads and builds the pinned upstream compiler, then fetches the
V modules and Vulkan headers into an isolated cache. An existing
V installation is not required. Later builds reuse that cache.

The default cache is `${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3/c0449e860641`;
`TT_V3_TOOLCHAIN_DIR` overrides it. To use the same toolchain for the direct
build and test commands below, configure the current shell:

```sh
tt_toolchain=${TT_V3_TOOLCHAIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3/c0449e860641}
export PATH="$tt_toolchain/v:$PATH"
export VMODULES="$tt_toolchain/modules"
export VULKAN_SDK="$tt_toolchain/Vulkan-Headers"
export V_MACOS_V3_NO_FALLBACK=1
```

### Windows

Open PowerShell with the CI-compatible V3 compiler, MinGW Clang, V modules and
`VULKAN_SDK` configured. The Windows helper expects those tools to be installed:

```powershell
.\scripts\build_windows.ps1
.\torus_trooper.exe
```

The helper finds GLFW through `GLFW_INCLUDE` and `GLFW_LIB`, or through
`glfw3:x64-mingw-static` in a configured vcpkg installation. It also checks the
isolated vcpkg checkout used by `antono2.glfw`. Set the two GLFW variables
explicitly if your installation is elsewhere.

To build and run the test suite, headless regression and Vulkan probe together:

```powershell
.\scripts\build_windows.ps1 -Verify
```

Verification also requires Python 3 and the Vulkan SDK shader tools. The Vulkan
probe requires a graphics driver and display session.

### Direct builds

With the matching toolchain and modules configured, a Linux source build can
use these commands:

```sh
v -cc gcc -o torus_trooper .
./torus_trooper
```

`v run .` compiles before launching. A reusable executable opens its window
immediately and shows initialization progress while preparing graphics and audio.
On Linux, a graphical executable built with V's default TinyCC relaunches once
through GCC to avoid a Volk/GLFW symbol collision; headless TinyCC runs execute
directly.

### Optional OpenCL backend

```sh
v -d opencl_compute -cc gcc -o torus_trooper .
./torus_trooper --compute opencl
```

`--compute cpu` is the default. If OpenCL was not compiled in, cannot initialize,
or produces a batch that differs from the CPU reference, the game uses the CPU
result and reports the fallback. See [Compute backends](#compute-backends) for
what is checked and which work remains on the CPU.

## Advanced settings and controls

### Option files and saved preferences

Place whitespace-separated options in `options.ini` in the working directory.
For configurable settings, command-line values override entries in that file;
explicit options take precedence over saved player preferences. Saved preferences
supply values that were not explicitly set.

```text
--window
--res 1280 720
--volume 0.35
--antialiasing 4
--near-blur 60
--near-fade 65
--rear-track-blend-percent 10
--track-draw-distance 75
--wire-draw-distance 120
--border-draw-distance 120
--fps-limit display
--bind-left left,a,kp_4
--bind-right right,d,kp_6
--bind-fire space,z,period,kp_decimal,left_control
--bind-charge left_shift,x,slash,left_alt
```

Settings changed from the menu take effect immediately and are saved in player
data. Discrete choices change once when horizontal input is released; continuous
sliders repeat while a key, stick or D-pad direction is held.

### Window, brightness and audio

| Option | Values and behavior |
| --- | --- |
| `--resolution WIDTH HEIGHT` | Window size; `--res` and `-res` are aliases. |
| `--fullscreen` | Borderless fullscreen on the primary monitor. F11 toggles it during play. |
| `--window` | Windowed mode, the default; `-window` is an alias. |
| `--brightness PERCENT` | `0–100`, default `100`. |
| `--luminosity PERCENT` | Luminous-entity intensity, `0–100`, default `80`; `--luminous` is an alias. |
| `--volume VALUE` | Master volume, clamped to `0–1`, default `0.35`. `--volume=0.35` is also accepted. |
| `--no-sound` | Avoid opening an audio device; `-nosound` is an alias. |

The brightness and luminosity options also accept their single-dash spellings.
Changing the menu's volume slider previews a music track for three seconds after
the last adjustment.

### Graphics and frame pacing

| Setting / option | Range | Default |
| --- | --- | --- |
| Anti aliasing / `--antialiasing` (`--msaa`) | `1`, `2`, `4`, `8`; `1` appears as OFF | `8` |
| Near blur / `--near-blur` | `0–100` percent | `80` |
| Near fade / `--near-fade` | `0–100` percent | `65` |
| Rear track blend / `--rear-track-blend-percent` | `0–100` percent | `10` |
| Panel distance / `--track-draw-distance` | `0–999` panel rows | `75` |
| Wire distance / `--wire-draw-distance` | `0–999` course slices | `120` |
| Border distance / `--border-draw-distance` | `0–999` course slices | `120` |
| FPS limit / `--fps-limit` | `60`, `display`, `unlocked` | `unlocked` |

Unsupported MSAA requests fall back to the highest color-and-depth sample count
supported by the selected GPU. Near blur and fade increase from the ship's screen
radius toward the viewport edge, keeping the ship vicinity and HUD sharp.

Panel, wire and border distances are independent. Borders remain visible when
panels and wire are both set to zero. Fully walkable tunnel sections use sparse
yellow square rings; sections with side edges mark those edges. Setting border
distance to zero hides the markers.

Rear track blend controls the end of the closed-panel region: `0%` uses the camera
plane and `100%` uses the last solid panel. Gaps close and wire coverage fades
toward the camera. The aliases `--rear-track-blend` and
`--no-rear-track-blend` select `10%` and `0%` respectively.

`display` follows the refresh rate of the monitor containing most of the window.
Both `display` and `unlocked` prefer mailbox or immediate presentation, with FIFO
as a device fallback. The `60` mode uses synchronized FIFO presentation and frame
pacing. Press F to show or hide the measured presentation rate.

Shot distance is a separate gameplay setting: the menu accepts `2–200`, with a
default of `75`. It is stored as `player_shot_distance` in `object_sizes.json`
and applies to ordinary, side and charged shots.

### Difficulty and starting level

```sh
./torus_trooper --grade hard --level 5
```

Grades are `normal`, `hard` and `extreme`, with aliases `n`, `h` and `e`.
`--grade=hard` and `--level=5` are also accepted. The title menu lets you choose
unlocked starting levels independently for each grade. Every new run receives
a fresh random seed; recordings retain it for deterministic playback.

### Custom bindings

Every input action is rebindable. Each value is a comma-separated binding list;
command-line values override earlier entries from `options.ini`:

```text
--bind-left KEY[,KEY...]
--bind-right KEY[,KEY...]
--bind-up KEY[,KEY...]
--bind-down KEY[,KEY...]
--bind-fire KEY[,KEY...]
--bind-charge KEY[,KEY...]
--bind-pause KEY[,KEY...]
--bind-restart KEY[,KEY...]
--bind-back KEY[,KEY...]
--bind-volume-down KEY[,KEY...]
--bind-volume-up KEY[,KEY...]
--bind-fullscreen KEY[,KEY...]
--bind-fps KEY[,KEY...]
```

Binding names are case-insensitive; hyphens and spaces may replace underscores.
Up to 24 bindings can be assigned to one action. The accepted strings are:

- Keyboard: `a` through `z`, `0` through `9`, and `f1` through `f25`.
- Direction/navigation: `up`, `down`, `left`, `right`, `page_up`, `page_down`,
  `home`, `end`, `insert`, `delete`, `tab`, and `backspace`.
- Common keys: `space`, `enter`/`return`, `escape`/`esc`, `pause`, `menu`,
  `caps_lock`, `scroll_lock`, `num_lock`, and `print_screen`.
- Punctuation: `plus`/`equal`/`+`/`=`, `minus`/`-`, `comma`, `period`,
  `slash`, `semicolon`, `apostrophe`, `left_bracket`, `right_bracket`,
  `backslash`, and `grave`.
- Modifiers: `shift`/`left_shift`, `right_shift`, `ctrl`/`control`/
  `left_control`, `right_control`, `alt`/`left_alt`, `right_alt`,
  `super`/`left_super`, and `right_super`.
- Numeric keypad: `kp_0` through `kp_9`, `kp_add`, `kp_subtract`,
  `kp_multiply`, `kp_divide`, `kp_decimal`, `kp_equal`, and `kp_enter`.
- Standard gamepad buttons: `gamepad_a`, `gamepad_b`, `gamepad_x`,
  `gamepad_y`, `gamepad_left_bumper`, `gamepad_right_bumper`, `gamepad_back`,
  `gamepad_start`, `gamepad_guide`, `gamepad_left_thumb`,
  `gamepad_right_thumb`, and `gamepad_dpad_up/right/down/left`.
- Standard gamepad axes: `gamepad_left_stick_left/right/up/down`,
  `gamepad_right_stick_left/right/up/down`, `gamepad_left_trigger`, and
  `gamepad_right_trigger`. The `controller_` prefix is an alias for `gamepad_`.
- Generic controllers: `joystick_button_1` through `joystick_button_16`, plus
  `joystick_axis_1_negative`/`positive` through
  `joystick_axis_8_negative`/`positive`.

`--bind-brake` aliases `--bind-charge`; the restart binding also starts a run
from the title screen. The fullscreen binding defaults to `F11`, and the FPS
overlay binding defaults to `F`.

`--reverse` (or `-reverse`) swaps the primary fire and charge controls. See the
[control table](../README.md#controls) for standard keyboard and gamepad bindings.
Keyboard Escape or controller Start opens the menu during a run. At the start
menu, Escape, Start or B resumes the suspended run; nested menus close first.
Choose EXIT to quit with a suspended run.

## Saved data and replays

### Files and locations

The game stores its configuration beneath the platform configuration directory
in a `torus_trooper` folder. `player.json` holds scores, unlocked levels, saved
settings and the replay library. `object_sizes.json` holds object scales and shot
distance. Exported recordings normally go in the adjacent `replays` directory.

| Option | Purpose |
| --- | --- |
| `--data-file PATH` | Use a different player-data file, including its scores and replay library. |
| `--object-sizes-file PATH` | Use a different size and shot-distance file. |
| `--model-file PATH` | Use another tuning-preview model file instead of `models/tune_models.json`. |

High scores and completed runs are saved when game over begins. Opening the menu
suspends a live run for later resume; replacing that run or quitting saves its
recording. Game-over return input unlocks after one second, and inactivity returns to the
title after twenty seconds. Menu/replay transitions last half a second; the
game-over fade lasts two seconds. These durations use monotonic elapsed time
and remain the same at different display frame rates.

### Replay files and playback

The REPLAYS menu supports names, local recording times, scores, durations, grades,
starting levels, sorting, import, export and removal. See
[replay controls](../README.md#watch-and-share-replays) for its keyboard shortcuts.
Deleting a library entry leaves exported files intact.

Portable `.ttr` recordings use a versioned JSON format. Imports validate the
grade, level, input bits and shot range, with a 16 MB file limit and a one-hour
recording limit. Imported results do not award personal bests or unlock levels.
Recordings preserve the seed, fixed-tick logical inputs, shot range and game mode.
Playback requires compatible simulation rules; a file-format version alone does
not guarantee compatibility with future gameplay changes.

Library recordings open in the original player view with the gameplay HUD.
During playback, Left selects the cinematic camera, Right selects the player
view, Up shows the HUD and Down hides it. The title-screen attract replay is
silent and uses the cinematic camera.

## Development tools and runtime

For source changes, the [code and tuning map](code-map.md) lists the files for
gameplay constants, display defaults, colors and input encoding, with units and
examples of what changing each value does.

### Object sizes and model previews

Open the silent tuning scene directly:

```sh
./torus_trooper --tune --object-sizes-file ./my-object-sizes.json
```

| Control | Action |
| --- | --- |
| Tab / Shift+Tab | Focus the next / previous labeled object. |
| Mouse or A/D | Orbit the focused object. |
| W/S | Move the camera closer / farther. |
| Space | Toggle automatic orbit. |
| + / − | Resize the selected object in `0.1` steps. |
| Backspace | Restore its default size. |
| Ctrl+S | Save the complete size catalog. |
| Ctrl+R | Reload sizes and preview models from disk. |
| Escape | Return to the title menu. |

Object scales range from `0.1` to `5`. Scene labels map to lowercase JSON keys,
such as `ENEMY_MIDDLE` → `enemy_middle`. Saved sizes affect ordinary gameplay.
The tunnel scale changes radial and longitudinal distances together, keeping
actors aligned with the course.

Optional recipes in `models/tune_models.json` affect tuning previews only.
Valid file edits reload automatically; invalid edits leave the last good model
visible. [Model tuning](../TUNING.md) explains the part types, coordinates and
file editing workflow. Reloading files does not reload compiled V code or shaders.

### Diagnostic overlays and effects

```sh
./torus_trooper --no-sound --volume 0 --debug-view=boundaries,slices,enemies,collisions,exhaust
```

Use any comma-separated subset of those overlays, `all` for all five, or `off`
to disable them. They help inspect course geometry, collision proxies and exhaust
placement without changing gameplay or replay state.

`--test-effects` runs an automatic sequence of firing, destruction, multiplier,
time-bonus, music, damage and game-over events between 2 and 13 seconds after
startup. It disables persistence. Add `--no-sound --volume 0` for silent checks.
`--test-object-tuning` opens a stationary tuning view without pointer capture and
closes after 300 presented frames.

### Simulation and rendering

Gameplay advances at a fixed 60 Hz. Presentation interpolates the course and its
actors between ticks, so display frame rate does not change simulation decisions
or replay input indexing. Tunnel cutoffs use depth planes and continuous fades;
the panel, wire and border streams keep their separate distance settings.

Solid hulls and projectiles use depth and opacity blending; particles retain an
additive glow. Procedural hull markings remain attached to their geometry, with
patterns selected by run seed, level and zone. Player and enemy trim, dark seams
and bright shot cores provide contrast on both light panels and dark openings.
The HUD and multiplier notices remain sharp above the near-camera effects.

The renderer uses persistently mapped, host-visible, host-coherent vertex buffers
managed by the V allocator. Detailed geometry, buffer ownership, interpolation
and material explanations are in [Rendering and assets](guide/05-rendering.md).

### Audio lifecycle

The ten effects in `sounds/chunks` are preloaded into eight fixed playback
channels. Effects sharing a channel intentionally interrupt one another.
The four PCM WAV music tracks are decoded during startup and loop from memory.
Their order depends on the run seed and rotates with completed level pairs.
Audio resources close with the runtime; failures are reported without stopping
silent gameplay. See [Runtime and audio](guide/06-runtime-and-audio.md).

### Compute backends

CPU execution is the default. The optional OpenCL build reuses a context, queue,
program and growing buffers for particle, hostile-bullet, released-shot and
enemy motion. Device compaction preserves original pool indices.

OpenCL can also generate potential shot/enemy and charged-shot/bullet collision
pairs. The CPU retains ordered collision resolution, scoring, spawning, charging
and lifecycle decisions. Each device batch is checked against the CPU reference;
a mismatch uses the CPU result. This preserves deterministic replay and adds
validation cost, so enabling OpenCL is not a promise of higher performance.

Headless reports include gameplay, render, course and compute checksums, verified
and mismatched batches, per-workload mismatch counts, and maximum numeric error.
Collision counters show active entities, tested pairs and emitted pairs. See
[Optional compute](guide/07-compute-and-verification.md) for the data flow and
tradeoffs.

## Verification

Use the configured build toolchain for these commands. Graphical checks need a
working Vulkan driver and a display or Xvfb session.

### Quick checks

```sh
# Initialize Vulkan without entering the game loop.
./torus_trooper --probe --no-sound --volume 0

# Run a deterministic simulation without a display.
./torus_trooper --headless --ticks 600 --no-sound --volume 0

# Check option parsing, fonts, simulation and runtime rules.
v -cc gcc test torus_trooper_test.v
v -cc gcc test font5x7 sim runtime
```

### Keyboard and replay interaction

```sh
xvfb-run -a bash scripts/test_replay_ui.sh
```

This silent check uses temporary player data and covers keyboard menu/resume,
exact suspended-state restoration, replay saving, renaming, export/import,
sorting, playback, deletion and returning to the title. It requires Xvfb,
xdotool, xprop, stdbuf and Python. Set `TT_REPLAY_SCREENSHOTS` to a directory
and install ImageMagick to capture its screens.

### Complete regression script

```sh
./scripts/check.sh
```

The script checks documentation links, native tests, builds, fixed headless
checksums, CPU fallback and Vulkan initialization. It runs game invocations
with sound disabled. Optional environment variables extend it:

| Variable | Additional check |
| --- | --- |
| `TT_VISUAL_SMOKE=1` | Effects sequence and automatic object-tuning scene. |
| `TT_REPLAY_UI_SMOKE=1` | Keyboard menu/resume and replay library interaction. Run under Xvfb when no display is available. |
| `TT_OPENCL_SMOKE=1` | Build and run the checked OpenCL backend; requires an installed OpenCL device runtime. |

A headless checksum checks simulated data. Visual changes also need observation
of the affected scene. [Configuration and verification](guide/08-configuration-and-verification.md)
explains the scope of each check and platform-specific development loops.

### Compiler diagnostics

CI and `scripts/check.sh` fail when a game compilation emits a warning or notice
from maintained project sources. Windows verification (`build_windows.ps1 -Verify`)
uses the same check. Dependency diagnostics remain visible without being counted
as project warnings, and the separate V compiler bootstrap is outside this gate.
Run a checked compilation directly with:

```sh
python3 scripts/check_compiler_diagnostics.py -- v -cc gcc -o torus_trooper .
```

## Packaging

### Linux archive

After building, create an archive with its launcher and runtime libraries:

```sh
bash scripts/package_linux.sh torus-trooper-linux-x86_64.tar.gz
```

Packaging requires Python 3, `glslangValidator`, `spirv-val`, `patchelf` and the distribution's installed
runtime-library license notices. `play.sh` sets the working directory and adds
`lib/` to the library search path; the executable also has a relative search
path. Bundled library notices and a version manifest live in
`thirdparty/linux-runtime/`. The graphics driver and glibc remain system dependencies.

### Windows archive

```powershell
python scripts/package_windows.py torus-trooper-windows-x86_64.zip torus_trooper.exe
```

Windows packaging requires Python 3 and the Vulkan SDK shader tools
(`glslangValidator` and `spirv-val`). Both packagers compile shaders from the
current source and validate the results before writing the archive. They include
runtime assets, documentation and license notices.
The executable loads `shaders/`, `sounds/` and `models/` relative to its working
directory, so keep the extracted files together. The CI workflow also builds
and checks both archive formats.

## License

This V implementation uses the [MIT License](../LICENSE). Bundled audio retains
[Kenta Cho's license](../sounds/LICENSE.txt), and miniaudio retains
[its own license](../thirdparty/miniaudio/LICENSE). Linux runtime-library notices
are included in the Linux archive.
