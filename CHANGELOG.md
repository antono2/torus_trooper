# Changelog

## Unreleased

- Bundle GLFW, the Vulkan loader and X11 support libraries in Linux downloads,
  with a launcher and their distribution license notices.
- Open replay recordings in the original player view with the gameplay HUD,
  keeping the title-screen attract replay cinematic.
- Support controller Start/B menu navigation and resume suspended runs without
  resetting simulation, input recording, pause state, or music selection.
- Save suspended recordings when replaced or when quitting, keeping the replay
  library free of duplicate recordings from repeated menu visits.
- Produce Windows and Linux candidate archives in CI, including runtime assets
  and license notices, and probe the extracted Windows package.
- Add a replay library with recording time, score and duration, sorting, custom
  names, file import/export and removal. Preserve the previous saved replay.
- Preserve shot range and god mode in new recordings for consistent playback.
- Align the bitmap font's square dots to a regular grid of screen pixels.

- Prepare the desktop source tree for release, add a Linux archive builder that
  includes runtime assets and license notices, and check guide links in CI.
- Provide independent panel, wiremesh, and track-border draw distances in
  SETTINGS and on the command line, including markers for fully walkable sections.
- Fade new tunnel panels through a fixed camera-relative plane and preserve
  their opacity across recycled rows so distant panels emerge smoothly.
- Reuse angular samples across course rows to reduce geometry preparation work.
- Add opt-in course, enemy, collision, and exhaust diagnostic overlays, plus
  annotated course and ship-proxy figures in the design guide.
- Add a design guide focused on this game's architecture and production choices.
  Remove unused XML barrage files and the obsolete comparison checklist.
- Replace the rear-track blend toggle with a saved 0–100% slider spanning the
  camera plane to the last solid panel. Blend panel gaps and wiremesh against
  the same endpoint, with migration for existing on/off player settings.
- Pin the latest Vulkan 3.1.0 and OpenCL bindings after exercising both the
  normal and OpenCL-enabled game builds.
- Taper tunnel-wire sample coverage with camera distance, using Vulkan MSAA
  alpha-to-coverage (and an alpha-blended 1x fallback) so densely packed far
  rings become sub-pixel lines instead of merging into a solid surface.
- Restore the player's segmented racer silhouette while keeping
  the small, middle, and boss enemies on their distinct solid 3D hull families.
- Make keyboard, standard gamepad, and generic joystick buttons and axes use
  the same configurable action bindings, and document every accepted binding
  string and controller alias.
- Apply SETTINGS adjustments once on horizontal-input release instead of
  repeatedly cycling values while a key, stick, or D-pad direction is held.
- Remove every hostile bullet and its active pattern state on the exact player
  respawn tick, including bullets emitted during that tick, so death cannot
  accumulate an unavoidable cloud around the returning ship.
- Adopt `torus_trooper` as the canonical module, executable, configuration
  directory, CI artifact, and GitHub repository name; keep the developer-only
  godmode sequence out of player-facing documentation.
- Raise the default high-resolution visual scales to 2x for the player, 3x for
  player shots and ordinary enemies, and 4x for boss hulls, hostile bullets,
  particles, and the tunnel.
- Expand TRACK DRAW to 0–999 solid panel rows, grow the Vulkan course buffers
  for the full range, and keep the wiremesh dense through the shared cutoff
  plane before its distant preview begins.
- Pace DISPLAY mode from the refresh rate of the monitor containing the window
  and use non-blocking Vulkan presentation where available, fixing 165 Hz
  secondary displays being limited by a 60 Hz monitor.
- Expand the speed HUD to five digits so 10000 KM/H retains its leading digit.
- Reshape player and enemy hulls as low, elongated racing spacecraft with
  swept wings, canopies, and engine pods. Use a centered course tangent and
  compensate oversized player tails so close-camera hulls remain stable.
- Reduce the ship's lateral track-border collision inset and ease contact while
  retaining an immediate clamp when its center actually leaves the track.
- Add a bindable `F` FPS HUD toggle and document it on the hotkey help page.
  Add persistent 60, display-synchronized, and unlocked presentation modes;
  unlocked mode selects mailbox/immediate Vulkan presentation when supported.
- Keep the selected FPS limit visible while SETTINGS is open instead of
  overwriting it with the Extreme high score during title HUD composition.
- Preserve saturated seeded colors on racing hulls under high brightness and
  luminosity instead of clipping their RGB channels to white.
- Round the small-interceptor fuselage with octagonal sections and sharpen boss
  silhouettes with longer nose prongs, outer wing points, and rearward fins.

- Replace the low-resolution, nearly direction-symmetric procedural ship panels
  with distinct volumetric player, small, medium, and boss hulls. Each uses a
  sharp +Z nose, flat -Z exhaust, real thickness, and the existing seeded color.
- Keep the TUNE camera at a fixed per-object distance and resize in clear 0.1x
  steps so adjustments have an immediate, proportional visual effect instead
  of being offset by auto-zoom. Direction-colored nose and exhaust caps make
  the new hull orientation readable when nearly head-on.
- Remove the enemy-only 180-degree model reversal so player and enemy ship
  shapes share a course-forward longitudinal orientation.
- Shift the player's five-unit longitudinal range from 0..5 to -2.5..2.5 so it
  can move closer to the chase camera and only half as far down the tunnel.
- Interpret TRACK DRAW as the exact number of visible panel rows and terminate
  their inset far edges on one shared depth plane before the wiremesh preview.
- Use a conservative bank-independent surface clearance for scaled ship hulls,
  preventing their noses from bobbing as wide wings roll near the camera.
- Extend the default solid-panel horizon from 54 to 64 panel rows and add a
  persistent SETTINGS/`options.ini` control for the panel-row distance.
- Composite the scrolling hit-multiplier list after the near-camera post pass,
  keeping it sharp without leaving an untreated rectangle in the tunnel.
- Align the volumetric hull longitudinal axis to two points sampled from the
  rendered tunnel surface, with bank applied only around that flight axis.
- Convert model-local Z with the source's five-unit slice depth instead of the
  radial tunnel scale, restoring the length of player, enemy, and boss hulls.
- Hide the superseded flat player/enemy cards during gameplay so they no longer
  mask the corrected course-relative volumetric hull orientation.
- Keep the procedural volumetric player and enemy hulls active in the normal
  chase camera instead of reverting to flat instanced cards after the
  course-relative rotation correction.
- Restore ship transform order so curved-course hulls are not locked
  to a shared tunnel axis.
- Add a persistent rear-track blend toggle that grows panel insets and blends
  them into the wire color from the ship toward the camera.
- Make rear-track blending close earlier in the short camera-to-ship interval,
  wrap its ON/OFF selector in both directions, and allow horizontal keys to
  activate non-adjustable menu entries.
- Slow the PAUSE overlay blink to half speed and reduce hull back/edge opacity
  so ship silhouettes remain recognizable with 3D thickness.

- Add a persistent 0-100 percent near-camera accessibility blur. A dedicated
  Vulkan post-process keeps the HUD sharp and progressively softens the region
  from the ship toward the viewport edge without temporal feedback.
- Add an independent near-camera fade that progressively blends the same region
  into the stable game background, further damping abrupt panel transitions.
- Add configurable Vulkan 1x/2x/4x/8x multisample anti-aliasing with automatic
  device fallback, live title-screen changes, and persistent configuration.
- Label the Vulkan 1x sample mode as OFF in Settings to make its disabled
  anti-aliasing behavior explicit.
- Replace the crowded title footer controls with a dedicated SETTINGS panel
  for volume and anti-aliasing, retaining responsive spacing on narrow windows.
- Store the bitmap font once per character and compose title, menu, pause, and
  game-over text from character codes instead of duplicated word bitmaps.
- Keep course-oriented instanced player/enemy bodies in the normal gameplay
  projection, reserving volumetric hull meshes for 3D replay and tuning views.
- Anchor the start-screen wordmark to the rotating torus silhouette so it
  follows the outer edge smoothly with a stable resolution-independent gap.
- Space the object-tuning gallery across a larger world grid and add
  Tab/Shift+Tab focus cycling that moves the camera to each selected object.
- Replace tuning free-look drift with object-centred mouse/A-D orbit and W/S
  dolly controls, allowing every model to be inspected from all sides.
- Render player and enemy tuning previews with their volumetric procedural
  meshes instead of screen-facing cards, while retaining the selection frame.
- Predecode music during the visible loading phase and reset frame timing after
  gameplay initialization, preventing slow storage from appearing as a multi-second
  low-FPS game start.
- Expose player-shot distance in SETTINGS and adopt the requested version-2 object
  scale and presentation defaults.
- Fade the rear-course wiremesh as its panel gaps close, and give hostile hulls,
  bullets, and boss bits a dark-edge/hot-core palette that contrasts with both
  bright track panels and dark openings.
- Derive extra inward ship clearance from each procedural hull's transformed
  radial bounds, preserving size-1 placement while preventing configured
  larger hulls from growing through tunnel panels.
- Drive the blinking pause overlay from wall time instead of frozen simulation
  time, so it continues alternating between labelled and clear screenshots.
- Render procedural player and enemy structures as closed,
  three-dimensional Vulkan hull meshes, including panel side walls and rocket
  bodies, so oblique gameplay and replay views retain visible volume.
- Project those hull vertices in their reconstructed 3D tunnel frame in both
  the normal gameplay camera and cinematic replay, so banking on a curved
  course no longer collapses ships onto a track-relative screen axis.

- Project ship and enemy bank across a stabilized transverse chase-view plane,
  and reconstruct an orthonormal three-dimensional tunnel frame for cinematic
  views, so model-Z roll foreshortens around the actual flight tangent instead
  of clamping hulls to a screen or track axis.
- Keep the tunnel mesh seam a guarded full tile behind the actual gameplay or
  cinematic camera and rely on homogeneous clipping instead of a title-only
  fragment discard, removing the replay's blinking circular panel cut.
- Add a bounded `player_shot_distance` gameplay setting to `object_sizes.json`
  and apply it consistently to ordinary, side, and charged shots.
- Replace the flat billboard orientation shortcut with a projected tunnel-local
  forward/circumferential/radial frame for every course-bound visual.
- Preserve ordered 3D rotations as per-instance quaternions: hull
  bank, bullet direction/spin, shot axis/spin, boss-bit tumble, and fragment
  tumble no longer collapse unlike axes into one screen-space angle.
- Open the native game window before renderer setup and show staged Vulkan,
  mapped-memory, and audio loading progress.
- Move the difficulty cards upward and add more responsive vertical padding.
- Remove inactive SDL/VGL git submodules and bundled BulletML C++ sources.
- Halve the ship's longitudinal travel while preserving its
  travel time, speed curve, and sight curve.
- Document and test that tunnel palettes start from the selected level and
  advance with each completed level pair.
- Preview game music for three seconds after the title volume slider changes.
- Removed the inactive SDL/OpenGL port and bundled GLAD loader. The repository
  now has a single GLFW `GLFW_NO_API` and Vulkan presentation path.
- Enforced an SDL/VGL/OpenGL-free active source graph and native binary linkage.
- Reworked the title menu into responsive per-difficulty level and record cards.
- Moved multiplier notices into a non-overlapping newest-first screen-edge list.

## 0.23.0 - 2026-09-09

- Replaced the active SDL/OpenGL/BulletML path with a native V simulation,
  GLFW input/windowing, and a Vulkan renderer.
- Restored deterministic stage progression, generated enemy specifications,
  the native barrage catalog, course behavior, scoring, timing, particles,
  replays, persistent player data, title flow, and the segmented HUD.
- Added vendored miniaudio effects/music playback with explicit lifecycle and
  silent fallback behavior.
- Added CPU structure-of-arrays compute boundaries for particle, bullet, shot,
  and enemy motion, plus rolling checksums and differential helpers.
- Added an opt-in `antono2.opencl` backend with reusable device resources,
  bit-exact live verification, diagnostics, and mandatory CPU fallback.
- Fixed Vulkan push-constant range validation and swapchain presentation
  semaphore reuse.
- Added deterministic regression, shader validation, GCC/TinyCC, OpenCL, and
  cross-platform audio bridge CI coverage.
- Normalized repository file modes and removed imported temporary files and
  compiled BulletML build products.
