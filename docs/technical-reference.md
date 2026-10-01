# Desktop technical reference

[Back to the game](../README.md) · [Design guide](learning-path.md) ·
[Source repository](https://github.com/antono2/torus_trooper)

Build commands and file paths below assume the repository root as the working
directory. This reference covers source builds, advanced configuration, runtime
implementation, diagnostics, and release verification.

## Release candidate status

The initial desktop release targets Linux and Windows. Linux is checked locally
with deterministic tests, a Vulkan display probe, and the complete replay
library workflow.
Windows has been checked locally with the V3 tests, a Vulkan probe, and a timed
graphical scene before the replay-library changes; that update still needs a
Windows run. The macOS audio bridge has a CI check, but the complete graphical
game still needs a macOS run; official macOS support awaits hardware testing.
The current module version is `0.23.0`; the changes
in [CHANGELOG.md](../CHANGELOG.md) remain unreleased until final review.

A runnable distribution needs the executable alongside `shaders/`, `sounds/`,
and `models/`, with those paths resolved from the working directory. Include
`LICENSE`, `sounds/LICENSE.txt`, and `thirdparty/miniaudio/LICENSE` when
redistributing it. After building on Linux, use
`scripts/package_linux.sh` to make a local archive with a launcher that sets
the working directory. The executable still requires the system GLFW and
Vulkan libraries and a Vulkan-capable driver.

## Learn from the project

[Read the design guide](../docs/learning-path.md) for the architecture and its
implementation in this repository. It compares viable alternatives for
simulation, memory, replay, content, rendering, assets, native services, and
optional compute, with examples for different kinds of games. The guide also
explains which further decisions matter when preparing a game for release.
Contributors maintaining the guide can use the separate
[guide-writing notes](../.github/guide-writing.md).

## Desktop build requirements

- V3 (the tested CI toolchain is pinned in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml))
- GLFW 3
- a Vulkan 1.1 loader and Vulkan-capable driver
- Vulkan 1.4.363 development headers, matching the generated binding registry
- `antono2.vulkan` 3.1.0 and `antono2.vkmemalloc` 2.6.0 or newer (which uses
  `antono2.memory` 1.4.0)

The optional OpenCL compute build additionally needs an OpenCL development
loader, an installed device runtime, and `antono2.opencl` 1.0.0 or newer.

Audio uses the vendored miniaudio 0.11.25 release and needs no separate audio
development package. If audio device creation or asset loading fails, the game
logs the reason and continues silently.

On Debian or Ubuntu the native packages are typically `libglfw3-dev`,
`libvulkan-dev`, and a suitable Mesa or vendor Vulkan driver.
The distribution's Vulkan headers may be older than the generated bindings;
point `VULKAN_SDK` at a Vulkan SDK or Vulkan-Headers checkout with header
version 363 or newer. The Vulkan loader and driver need not be that new.

On Windows 10/11 x64, open PowerShell with `v`, a Windows x64 MinGW Clang
toolchain, and `VULKAN_SDK` available,
then run:

```powershell
.\scripts\build_windows.ps1
.\torus_trooper.exe
```

The script uses MinGW Clang and reuses
`GLFW_INCLUDE`/`GLFW_LIB`, a configured vcpkg installation, or the isolated
vcpkg checkout created by `antono2.glfw` setup when it contains
`glfw3:x64-mingw-static`. Set `GLFW_INCLUDE` and `GLFW_LIB` to a MinGW GLFW
installation if that triplet is not installed.
It does not install packages or change persistent environment variables.
Plain `v .` is also supported when `GLFW_INCLUDE` and `GLFW_LIB` already point
to a compatible GLFW installation; the script handles discovery automatically.
Run `.\scripts\build_windows.ps1 -Verify` to also run the V3 tests, a 600-tick
headless run, and a Vulkan initialization probe. The probe requires a working
Vulkan driver and display session.

## Build and run

On Linux, the simplest reproducible V3 build is:

```sh
bash scripts/build_linux_v3.sh
./torus_trooper --no-sound --volume 0
```

The script keeps a tested V3 compiler and Vulkan-Headers 1.4.363 in
`~/.cache/torus-trooper-v3` (override with `TT_V3_TOOLCHAIN_DIR`). It does not
replace your installed `v` or Vulkan SDK. Install `git`, `make`, `gcc`,
`libglfw3-dev`, and `libvulkan-volk-dev`, then run `v install` once for the V
modules if necessary. The first build downloads and compiles the toolchain;
later builds reuse it. A direct `v -cc gcc -o torus_trooper .` build requires
`VULKAN_SDK` to point at Vulkan-Headers 1.4.363 or newer.

Alternatively, with that toolchain already configured:

```sh
v install
v run .
```

For a reusable executable, build with a system compiler:

```sh
v -cc gcc -o torus_trooper .
./torus_trooper
```

The executable maps its window immediately and displays Vulkan initialization
progress while it creates the swapchain, render pipelines, mapped buffers, and
audio device. `v run .` must compile before it can launch that window; build the
reusable executable once when subsequent starts should open without that compile
delay.

On Linux, a graphical build started with V's default TinyCC automatically
restarts once with GCC. This avoids an ELF symbol collision between Volk's
dispatch variables and GLFW/Vulkan loader functions; headless TinyCC builds
continue to run directly.

The V-native Vulkan allocator suballocates the three persistently mapped vertex
streams from compatible shared memory. Its policy requires host-visible,
host-coherent upload memory, while checked ownership and diagnostics replace the
renderer bridge's former per-buffer allocation and teardown code.

Build the optional OpenCL motion backend with:

```sh
v -d opencl_compute -cc gcc -o torus_trooper .
./torus_trooper --compute opencl
```

Without `-d opencl_compute`, requesting OpenCL remains valid and reports why
the deterministic CPU fallback was selected. With the feature enabled, the
game creates one reusable context, queue, program, and capacity-growing buffer
per workload. A shared typed dispatch helper now owns the repeated buffer
growth, upload, kernel argument, dispatch, and download sequence. Initialization
or runtime errors also fall back without aborting the game.

## Advanced settings and controls

The master sound volume defaults to `0.35`. Set it anywhere from silent (`0`)
to full (`1`):

```sh
./torus_trooper --volume 0.35
```

Values outside the range are clamped. `--volume=0.35` is also accepted.
Use `--no-sound` (or its `-nosound` alias) to avoid opening an audio device.

Vulkan multisample anti-aliasing defaults to 8x. Select 1x (shown as `OFF` in
Settings), 2x, 4x, or 8x with `--antialiasing` (or `--msaa`); unsupported
requests fall back to the highest color-and-depth sample count exposed by the
selected GPU:

```sh
./torus_trooper --antialiasing 4
```

Set display brightness and luminous-entity intensity as percentages:

```sh
./torus_trooper --brightness 85 --luminosity 65
```

Both accept values from `0` to `100`; `--luminous` and the single-dash
spellings are accepted as aliases. Defaults are `100` and `80`, respectively.

Choose a window resolution with `--resolution 1920 1080`, `--res`, or the
`-res` spelling. Use `--reverse` (or `-reverse`) to swap the primary
fire and charge-shot controls.
Windowed mode is the default; `--fullscreen` starts in borderless fullscreen on
the primary monitor. F11 toggles borderless fullscreen without restarting.
`--window` and `-window` explicitly select windowed mode.

For visual diagnostics, `--debug-view=boundaries,slices,enemies,collisions,exhaust`
enables any comma-separated subset of those overlays. `--debug-view=all`
enables all five and `--debug-view=off` disables them. The overlay is
presentation-only and does not affect collisions or replays. It is intended
for inspecting the course and ship geometry, not normal play.

Options can also be stored in an `options.ini` file
in the working directory. Whitespace-separated options from that file are read
first, so command-line options take precedence. For example:

```text
-window
-res 1280 720
-brightness 85
-luminosity 65
--volume 0.35
--antialiasing 4
--near-blur 60
--near-fade 65
--rear-track-blend-percent 10
--track-draw-distance 64
--wire-draw-distance 120
--border-draw-distance 120
--fps-limit display
--bind-left left,a,kp_4
--bind-right right,d,kp_6
--bind-fire space,z,period,kp_decimal,left_control
--bind-charge left_shift,x,slash,left_alt
```

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

The title screen provides three difficulty grades and unlocked
starting-level selection. You can also preselect them on the command line:

```sh
./torus_trooper --grade normal
./torus_trooper --grade hard
./torus_trooper --grade extreme
```

The short forms `n`, `h`, and `e`, and `--grade=hard`, are also accepted.
Choose an unlocked starting level with `--level 5` or `--level=5`.
Each newly started game receives a fresh MT19937 seed; the stored replay retains
that exact seed for deterministic playback. The same seed chooses a non-repeating
first music track and whether completed level pairs rotate forward or backward
through the four-track set.

Run the short automatic audio/visual regression sequence with:

```sh
./torus_trooper --test-effects
```

It labels and triggers charge, all enemy destruction tiers, floating multiplier
feedback, both zone bonuses, music rotation, player damage, score extension,
warning beeps, and game over
between 2 and 13 seconds after startup. This mode is only for testing.

Controls:

- On the title screen, Up/Down selects a menu item; Left/Right adjusts LEVEL or
  the HELP page. SETTINGS contains persistent volume, Vulkan MSAA, near-camera
  blur, near-camera fade, and rear-track blending controls.
- Primary fire or the restart/start binding starts the selected run
- After completing a run, the charge-shot control replays its recorded logical inputs
- During replay, Left selects the cinematic camera and Right selects ship-follow
- During replay, Up shows the gameplay HUD and Down hides it

The cinematic replay camera uses a seeded FLOAT/FIX state machine,
including three-axis camera drift, decaying look-at offsets, periodic reframing,
and bounded zoom targets. During cinematic replay, both Vulkan world pipelines
build a shared three-dimensional view basis from the eye and look-at positions,
including radial height and camera roll. Ship-follow and
normal gameplay retain their established projection path.

Enemy generation uses a shape seed for every zone spec. The
seed travels in the existing five-float instance stream and deterministically varies
the Vulkan silhouette within small (one or two shafts), middle
(three or four), and large (five or six) topology families.
The native geometry model constructs every `Structure` position,
rotation, dimension, primitive family, color, and division count from that seed;
collision and exhaust placement are derived from the same complete definition.
The fixed `ShipShape(1)` player topology is represented as the same seeded
twin-shaft, triangular-wing family, and boss bits use an eight-bar
radial cage silhouette.
Regular shots use a rotating four-blade form. The charged shot
uses eight triangular faces at radial distances
`0.1/0.5/1.0`, including their `0.2/0.5/-0.7` height profile and bright-to-dark
tip shading. Sparks,
jets, and distance-driven background stars are
velocity-aligned streaks; destruction fragments are independently rotating plates scaled by
enemy tier.
Hostile triangle, cube, and bar bullets rotate six degrees per tick. A cleared
or escaped bullet becomes its paired wireframe model, shrinks for
45 ticks without collisions, and reserves its pool slot until the effect ends.

- Left/Right or A/D: bank around the tunnel
- Up/Down or W/S: longitudinal control
- Space, Z, period, or Left Control: primary fire
- Hold Left Shift, Left Alt, X, or slash: charge shot; release after about 0.4
  seconds to fire. It penetrates enemies, clears bullets, and regeneratively
  slows the ship
- P: pause or resume the run
- Minus or keypad subtract: lower master volume by 5%
- Plus/equal or keypad add: raise master volume by 5%
- F11: toggle borderless fullscreen
- F: show or hide the measured presentation FPS in the HUD
- Enter or R: return to title selection after game over
- Escape: return an active game/replay to title; exit from the title screen

Numeric-keypad directions and first-controller mappings are defaults; all of
them can be replaced with the binding strings above.
After game over, Enter or R returns to title selection.
When a replay is available, it runs continuously and silently behind the title
selection; secondary fire enters
or leaves the full replay view without restarting playback. The world viewport
expands from four-fifths to full width (and retracts again) over a
30-frame handoff, with the title and gameplay HUDs shown only at their respective
endpoints. Escape returns from the replay view to title selection before it can
exit the application. The charge/replay command is disabled while HELP is
selected, so its pages cannot be replaced by an empty replay view.
On the title screen, Up/Down or W/S selects NORMAL, HARD, EXTREME, SETTINGS,
HELP, and EXIT before wrapping to NORMAL. Each difficulty card includes its own
starting-level selector and completion information.
Activating SETTINGS opens a dedicated, padded panel. Up/Down chooses VOLUME,
ANTI ALIASING, PANEL DISTANCE, WIRE DISTANCE, BORDER DISTANCE, SHOT DISTANCE, FPS LIMIT, NEAR BLUR, NEAR FADE,
REAR TRACK BLEND, or BACK. Left/Right adjusts the selected value, and Escape or
BACK returns to the main menu. NEAR BLUR defaults to 80
percent and can also be set from `0` (off) to `100` with `--near-blur`. NEAR
FADE defaults to 65 percent and uses `--near-fade`; at 100 percent the outermost
near-camera image is fully blended into the stable game background. Both effects
begin at the ship's screen radius and increase toward the camera edge, while the
ship vicinity and HUD remain sharp. Changes are applied immediately and saved in
the versioned player configuration. Activating EXIT closes the game.
FPS LIMIT cycles through `60`, `DISPLAY`, and `UNLOCKED`. `UNLOCKED` is
the default; `DISPLAY` detects the refresh rate of the monitor containing most of the
window, so moving the game between mixed-refresh displays updates its target.
It prefers mailbox presentation, then immediate presentation, to avoid an X11
FIFO swapchain being tied to a different monitor. `UNLOCKED` uses the same
non-blocking preference without frame pacing; both safely fall back to FIFO
when neither mode is available.
The 60 mode retains synchronized FIFO presentation and paces completed frames
to the selected rate. The same value can be selected in `options.ini` or on the
command line with `--fps-limit 60`, `display`, or `unlocked`. A 30 FPS limit is
intentionally unavailable because its coarse presentation made fast track motion lag.
REAR TRACK BLEND is a 0–100% slider. It sets where the closed-panel region ends:
0% is the camera plane and 100% is the last solid panel selected by PANEL DISTANCE.
The panel gaps close and the wiremesh fades toward the camera. The default is
10%. Left/Right moves the slider and saves the value in player data. The command
line also accepts `--rear-track-blend-percent 50`; the older
`--rear-track-blend` and `--no-rear-track-blend` flags select 10% and 0%.
PANEL DISTANCE controls the number of solid panel rows; WIRE DISTANCE
independently controls how many course slices of wiremesh are drawn. BORDER
DISTANCE controls the yellow markers along the walkable track edges. Fully
walkable tunnel sections have no side edges, so sparse square rings outline
their circumference. All three accept 0 through 999 in SETTINGS and default
to 75, 120, and 120 respectively.
They can also be set in `options.ini` or on the command line with
`--track-draw-distance 75 --wire-draw-distance 120 --border-draw-distance 120`.
Each cutoff is an independent depth plane. The track border remains visible when
panels and wire are both 0; setting BORDER DISTANCE to 0 hides it deliberately.
Hovering on HELP replaces the attract replay
inside the torus with three pages: the goal of the game, explanations for every
HUD field, and gameplay/menu hotkeys, including the configurable borderless-
fullscreen and FPS-overlay actions. Left/Right or A/D changes HELP pages and adjusts LEVEL;
holding an adjust key accelerates changes after a short delay. Volume changes
are saved with player data unless persistence is disabled.
Left or Right also activates SETTINGS, TUNE, EXIT, and the SETTINGS BACK item;
difficulty cards retain those keys for their level selectors. SETTINGS values
with discrete choices change once when the horizontal input is released. The
continuous VOLUME, PANEL DISTANCE, WIRE DISTANCE, BORDER DISTANCE, SHOT DISTANCE, NEAR BLUR, NEAR FADE,
and REAR TRACK BLEND values deliberately repeat while a key, stick, or D-pad
direction is held.

## Development tools and runtime

The developer-only TUNE menu opens a silent object-scale reference scene: WASD flies the free
camera, the mouse looks around, and the object under the crosshair receives a
cyan border. Plus/equal or keypad add enlarges it in visible 0.1x steps; minus
or keypad subtract shrinks it. Ctrl+S writes the complete catalog to
`object_sizes.json` in the
platform configuration directory, and Escape returns to the title menu. Every
object has an in-scene uppercase label such as `ENEMY_MIDDLE`; its saved JSON
key is the exact lowercase spelling (`enemy_middle`). The saved scales load on
the next start and apply to ordinary gameplay as well as the tuning scene. The
focused preview stays visible while gallery objects and labels crossing its view
are clipped; Tab can still move the focus to those objects. The same JSON also
contains `player_shot_distance`; its default is `75`, values from
`2` through `200` are accepted, and it scales
ordinary, side, and charged-shot travel consistently. Use
`--object-sizes-file PATH` to select a different file.
Player and enemy entries use distinct asymmetric low-poly racing hulls in TUNE
and in gameplay. Small interceptors use rounded octagonal fuselages, while boss
ships have long nose prongs, sharp outer wings, and rearward fins. The player
and medium ships retain low fuselages, swept wings, raised canopies, and engine
pods. A narrow nose identifies the flight direction, a flat rear identifies the
exhaust end, and real top, bottom, and side faces keep each class readable from
oblique views. Hue-preserving nose highlights and warm exhaust caps make that
direction explicit even when a ship is nearly head-on. TUNE identifies the
selected hull with its focused camera and title without replacing its color or
drawing the former flat selection card over it. Tab focus uses a fixed camera distance,
so a scale change remains visually proportional instead of being hidden by an
automatic zoom adjustment; W/S remains available for manual zoom.
Enemy hulls use a consistent longitudinal convention: after the
tunnel-surface rotations, their narrow noses face course-forward just like the
player hull. They are not flipped merely because their relative depth may be
decreasing as the player approaches them.
The labeled `TUNNEL` circle is selectable in the same way; its `tunnel` scale
changes radial and longitudinal world distances together, so actors remain
registered to the surface and keep scale relative to the tunnel. Solid panels
and wiremesh have independent draw distances; the yellow boundary markers
continue to whichever distance is longer to expose upcoming orientation.
For automated renderer checks, `--test-object-tuning` opens that scene directly
in a stationary godmode view and closes it after 300 presented frames; it does
not capture the pointer.
Game-over return input unlocks after one second, with an automatic title return
after twenty seconds of inactivity.
The help pages spell out compact HUD terms such as `STAGE PROGRESS`,
`BOSS DISTANCE`, and `KILOMETERS PER HOUR`. HUD and hotkey entries separate
their names from descriptions with ` - `, and alternate keys use comma-separated
lists. The gameplay HUD bottom-aligns
labels with score, time, the `NEXT +15` score target, level, `STAGE PROG`,
`BOSS DIST`, speed, and hits. When an aspect-derived field width cannot hold a
label and value inline, the layout places the value below its label instead.
HITS counts ship destructions rather
than remaining health: there is no fixed hit limit, but each hit costs 15
seconds and the run ends when TIME reaches zero. Gameplay glyphs use
translucent faces so the course remains visible through the
HUD. A resolution-scaled dark outline backs all labels and numbers without
changing their responsive anchors. Ordinary labels use one neutral color,
values use one brighter color, and only selections, warnings, and timed events
use semantic accents. Ordinary and hostile projectiles receive a
small local depth bias, while the large luminous super shot uses foreground
depth so its own course slice cannot cut through it.
Course-bound ships, shots, bullets, jets, and background star streaks derive
their screen orientation from the projected tunnel direction. They therefore
follow bends and cinematic replay cameras instead of sharing a fixed screen
axis; star trails radiate from the current flight vanishing direction.
The player's five-unit longitudinal movement range is centered on the neutral
start position. Half extends toward the chase camera and half down the tunnel;
rearward travel keeps the default speed and sight range.
Open-course borders slow and steer the ship without causing damage, while
insetting the border by its collision footprint across
narrowing and wrapped walkable sections.
The title HUD gives NORMAL, HARD, and EXTREME their own padded information card:
each card shows its independently selectable starting level, unlock limit, best
score, and the best run's start/end range under `DONE`. Left/right changes the
level on the active difficulty. The cards sit beside an animated white wireframe
torus and shader-drawn `TORUS TROOPER` wordmark. Its narrower tube and
right-shifted replay viewport provide a larger view close to the menu. The torus masks the attract
replay so the game remains visible through its opening while the labeled
right-side menu stays on a blank field. Three grade-colored selector rings and full NORMAL/HARD/EXTREME
labels identify the available grades, with the active grade using a
pulsing cursor. High scores with
those ranges, reached levels,
the last selection, and the replay library are saved as versioned JSON in the
platform configuration directory as soon as game over begins, so closing the
window from that screen loses nothing. `--data-file PATH`
selects another location; automated effects tests disable persistence.
The REPLAYS menu lists recordings with names, local recording times, scores,
durations, grades, and starting levels. It sorts newest first or by descending
score. Keyboard shortcuts and gamepad navigation are shown in the player
[README](../README.md#watch-and-share-replays). Import and export use portable
`.ttr` JSON files with a separately versioned format. Imports validate the
format, grade, level, input bits and shot range, with a 16 MB file limit and a
one-hour recording limit. They never award high scores or unlock levels.
The earlier single-replay save migrates into the library with an unknown date
and score if that metadata was not recorded. New recordings preserve shot range
and god mode alongside the seed and fixed-tick inputs. Returning to the menu
also saves unfinished runs. Deleting a library entry does not delete exported
files. Replay files should be played with this game's matching simulation rules;
a format version is not a guarantee of compatibility with future gameplay changes.

Adjusting the title-screen volume slider plays a regular music track for three
seconds after the latest change, making the selected level audible without
adding continuous title music.

A run starts with two minutes. Taking a hit removes 15 seconds, the final
15 seconds produce one warning beep per second, and reaching each score-extension
threshold restores 15 seconds up to the two-minute maximum. A Vulkan-native
segmented HUD shows score at the upper right, time at the upper center, level at
the lower left, hits at the lower right, speed and rank progress, and the score
remaining until the next time extension. Time bonuses and penalties flash their
signed second changes. The window title carries the
same values, while centered shader lettering presents the
blinking `PAUSE` and persistent `GAME OVER` states. Menu and gameplay text retain
explicit label/value padding at narrow aspect ratios instead of expanding into
adjacent fields. The upper-right `SCORE` and `NEXT +15` rows share a calculated
label edge, while each value follows its label by the same metric-derived gap,
so their alignment follows live framebuffer aspect changes.

Destroying each large enemy advances the zone. Alternating zones add 30 and 45
seconds (up to the two-minute cap); completed level pairs rotate the music and
increase enemy spawn rate, firing rate, and bullet speed.
Charged shots pierce targets and build a score multiplier up to `X100`;
successive kills add upright multiplier notices to a newest-first, non-overlapping
screen-edge list that remains visible above tunnel panels without obscuring the
central flight path.
The Vulkan effects layer distinguishes impact sparks, ship exhaust jets,
background star streaks, and enemy destruction fragments.
Destruction bursts scale from small craft through middle enemies and bosses;
player destruction emits a 256-particle core burst. The reusable
1,024-entry particle pool leaves room for that burst alongside the star field.
Hostile barrages retain their specification's triangle, square, or bar bullet
family, with animated filled/wire presentation variants.

World rendering uses a per-swapchain depth target. Open course segments discard
their fragments instead of writing depth, allowing farther tunnel geometry to
remain visible through the opening while nearer solid track correctly occludes
wireframes and actors. Tunnel rings advance continuously with the fractional
course position and accumulate curvature from the ship coordinate origin, so a
rear buffer-index change cannot jump the visible centerline. The distinct
camera plane remains four course units behind the ship, with another complete
slice retained behind it before geometry is recycled. Presentation-only
fixed-step interpolation advances the course and its bound actors on every
Vulkan frame, while gameplay remains deterministic at 60 Hz. Track and
surface-bound actors share the generated course center, local radius, and
longitudinal coordinate frame instead of approximating bends with a separate
animation. The ship, enemies, projectiles, and boss parts receive source-space
surface clearance plus a local depth bias so their complete shapes remain
inside the tunnel without defeating occlusion by nearer panels. Player
and enemy shots use the same sampled course center and radius, keeping fire on
the track through vertical and lateral bends. Enemy bullets retain their real
longitudinal depth: they sit above their emitting slice, but nearer tunnel walls
can still occlude them. Small, middle, and large enemy screen scales follow
wider tier-specific ratios and true reciprocal-depth perspective, which preserves
their physical footprint at any window resolution. The enlarged player renders
one partial slice nearer to emphasize its foreground position. Background
stars are distributed around the full tunnel, follow the same course bend on
the outside surface, and render on the background depth layer so solid panels
mask their moving streaks. The player uses a 1/1.05 surface inset and remains a
near foreground actor instead of being intermittently hidden by curved panels. Five
complete panels remain behind the ship across fractional course wraps, hiding
the near tunnel entrance and preventing flashes at slice boundaries. Panel
fill covers only the near half of the forward slices; the grid continues alone
into the distance so upcoming
curves remain readable. Grid width scales from a 480-pixel-tall reference
framebuffer and is clamped to the Vulkan device's supported wide-line range,
with a portable one-pixel fallback. Its coverage fades continuously along the
tunnel and reaches zero at the final ring, so the distant mesh becomes visually
thin before disappearing. Procedural enemies and shots keep their
screen-space proportions at higher resolutions without low-resolution raster
artifacts. The ship's longitudinal travel uses a 100-tick traversal time and
normalized speed response. Track color is bound to the integer level: starting
directly at a later level uses that level's
palette, and its intermediate half-level zone keeps the same color.

## Verification

Probe Vulkan without entering the render loop:

```sh
./torus_trooper --probe
```

Exercise the replay library silently on an isolated X display (requires
`xvfb`, `xdotool`, and Python):

```sh
xvfb-run -a bash scripts/test_replay_ui.sh
```

This checks saving an unfinished run, renaming, portable file export/import,
sorting, playback, deletion and returning to the title. It uses a temporary
player-data file and leaves existing scores and settings alone. The same test
runs in Linux CI with `TT_REPLAY_UI_SMOKE=1`. Set `TT_REPLAY_SCREENSHOTS` to a
directory to capture the screens, with ImageMagick installed.

Run the deterministic simulation without GLFW or a display:

```sh
./torus_trooper --headless --ticks 600
```

Headless output includes both the gameplay checksum and a five-float render-snapshot
checksum, plus the float4 procedural-course checksum, providing reference
results for a future OpenCL implementation. Active render entities are first
collected into structure-of-arrays storage, then validated and packed into the
Vulkan instance stream by the CPU reference backend. Particle movement also runs
through a compacted SoA CPU kernel with stable indices for scattering results
back into the gameplay pool; this is the first simulation workload isolated for
later CPU/OpenCL differential execution. Hostile-bullet translation uses the
same boundary after its native pattern pass, while collision decisions retain
their stable gameplay order. Player-shot movement is isolated in the same way;
charging, penetration, and enemy damage remain ordered CPU gameplay decisions.
Enemy translation and steering are also packed for the CPU compute backend,
while rank changes, course correction, firing, and lifecycle stay ordered.
All four workloads use one explicit dispatch layer with item and validation
statistics. `--compute cpu` is the default. An OpenCL-enabled build runs the
particle, hostile-bullet, player-shot, and enemy motion kernels on the selected
GPU (or the first available OpenCL device). Particle, hostile-bullet,
released-shot, and prepared-enemy dispatch upload their full pools and share
stable parallel mark, prefix-scan, and scatter passes on the device, preserving
source indices before running smaller motion ranges. Charging shots and enemy
steering decisions remain in their ordered CPU passes. The OpenCL backend also
builds stable shot-major/target-minor broad-phase collision candidate streams
for both player-shot/enemy hits and charged-shot/hostile-bullet clearing. Both use one
parameterized pair kernel and reusable scan storage. Eligible shots and live
targets are stably compacted on the device first, so pair expansion scales with
active entities rather than fixed pool capacities while retaining gameplay pool
indices. Each candidate stream is
checked exactly against its CPU reference before the established ordered CPU
collision pass consumes it, and mismatches automatically select the reference
stream. Live-state predicates are rechecked while consuming pairs because an
earlier hit can invalidate a later candidate.
During this correctness-first milestone, every OpenCL batch is checked against
the CPU reference bit for bit;
a numerically different batch uses the CPU result and is counted as a fallback.
This retains deterministic gameplay and replay checksums while exposing small
device-math differences before a later performance mode relaxes that guard.
Headless diagnostics also emit a rolling checksum of every post-kernel SoA
batch, allowing differences to be localized before they affect gameplay state.
Differential helpers compare stable indices and integer fields exactly while
reporting floating-point mismatch counts and maximum error at a chosen tolerance.
The headless report includes verified and mismatched batch counts, a per-workload
mismatch breakdown, and the maximum observed floating-point error. Collision
diagnostics additionally show
active shot and target totals, tested pair counts, emitted candidates, and exact
candidate mismatches, making compaction effectiveness visible without relying
on timing measurements.

Run the native V tests:

```sh
v test sim runtime
```

Run the complete non-interactive regression gate (tests, build, deterministic
headless checksum, and Vulkan probe) with:

```sh
./scripts/check.sh
```

Set `TT_VISUAL_SMOKE=1` to append the 16-second effects sequence. The script
always passes both `--no-sound` and `--volume 0` to every game invocation.
Set `TT_OPENCL_SMOKE=1` when `antono2.opencl` and an OpenCL device runtime are
installed to build the optional backend and require a deterministic 600-tick
OpenCL run.

The ten effects in `sounds/chunks` are preloaded. The four PCM WAV tracks in
`sounds/musics` are decoded during the visible loading phase and looped from memory;
they are lossless conversions of Ogg Vorbis music. Effect playback uses eight
fixed channels, including intentional interruption between
effects which share a channel.

## License

This V implementation is available under the [MIT License](../LICENSE).
Bundled audio remains under Kenta Cho's license in
[`sounds/LICENSE.txt`](../sounds/LICENSE.txt), and miniaudio retains its license in
[`thirdparty/miniaudio/LICENSE`](../thirdparty/miniaudio/LICENSE).
