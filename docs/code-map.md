# Code and tuning map

[Technical reference](technical-reference.md) · [Design guide](learning-path.md)

## Where to change what

| Change | Source | Effect |
| --- | --- | --- |
| Run time, weapon timing, respawn protection, ship response | [`sim/gameplay_tuning.v`](../sim/gameplay_tuning.v) | Changes simulation rules. Durations and response coefficients are grouped by purpose. |
| Difficulty | [`sim/rules.v`](../sim/rules.v) | Per-grade speed, bank and stage progression values. |
| Fresh-profile settings, window size, menu transitions | [`runtime/settings.v`](../runtime/settings.v) | Shared defaults for command-line parsing, runtime configuration and saved player data. Existing saved preferences still take precedence unless an option is explicit. |
| Object sizes and shot distance | [`runtime/object_sizes.v`](../runtime/object_sizes.v) | Default size catalog; the TUNE scene and `object_sizes.json` provide runtime overrides. |
| Level wire/panel and base hull colors | [`sim/palette.v`](../sim/palette.v) | Named RGB colors selected by the simulation and mesh generator. |
| HUD, projectile, particle and ship-trim colors | [`shaders/palette.glsl`](../shaders/palette.glsl) | Named colors shared by the rendering shaders. |
| Loading bar and background clears | [`runtime/vulkan_bridge.h`](../runtime/vulkan_bridge.h) | The `tt_loading_*` colors and `tt_background_navy`; keep the background equal to the shader palette's navy for a seamless near fade. |

## Units and behavior

- **Ticks** advance at 60 Hz. Increasing `charged_shot_min_ticks` makes the
  player hold charge longer before a shot can be released. Increasing
  `regular_shot_interval_ticks` reduces the ordinary firing rate.
- **Milliseconds and seconds** have explicit suffixes. The run clock consumes
  `run_clock_tick_ms` (17 ms) each tick for compatibility with existing gameplay
  and replays; this is separate from the 60 Hz simulation schedule.
- **Frames** count presentations. Increasing `menu_transition_frames` lengthens
  the fade at a given display frame rate. It does not change simulation speed.
- **Response coefficients** are applied each tick. Increasing
  `ship_acceleration_response` approaches the target speed sooner; reducing
  `ship_bank_retention` damps lateral movement more quickly. Brake energy capture
  and ordinary deceleration have separate constants even though their values
  currently match.
- **Distances** along the course use slices; lateral positions and gun offsets
  use radians around the tube. `relative_depth_step` changes forward/back travel
  per tick. Panel, wire and border draw distances have independent defaults.
- **Percentages** in settings use `0–100`. Color components and normalized
  volume use `0–1`. A color name describes its role and approximate hue, such as
  `color_shot_gold`; it does not imply a standard CSS color. Alpha, glow and
  brightness remain separate from the base RGB color.

Gameplay changes can change the outcome of an existing replay. Keep regression
checksums unchanged for readability-only edits; evaluate intentional gameplay
changes separately. Palette index order also affects seeded color selection.

## Encoding and geometry

Some numbers describe a data format rather than a visual or gameplay preference:

- [`sim/replay.v`](../sim/replay.v) names the six saved input bits.
  [`runtime/input.v`](../runtime/input.v) maps them to logical controls and adds
  pause, restart, back and volume actions. Their positions match `TTInputAction`
  in the C bridge.
- [`shaders/hud_state.h`](../shaders/hud_state.h) defines menu/gameplay state
  flags and packed FPS bits once for both C and GLSL.
- Mesh vertex coordinates, font bitmaps, array indices and mathematical
  identities stay close to the algorithms that use them. Their surrounding
  fields and layout comments explain the data; they are not global tuning knobs.

Use names that express the purpose and unit of a value. Share a constant when
the uses must stay in sync; equal numeric values alone do not make them the same
setting.

## Rebuild after editing colors

V palettes compile with the game. GLSL palettes compile into the shipped `.spv`
files; the runtime does not read shader source. With `glslangValidator` and
`spirv-val` installed, rebuild and validate from the repository root:

```sh
for source in shaders/*.vert shaders/*.frag; do
    glslangValidator -V "$source" -o "$source.spv"
    spirv-val "$source.spv"
done
```

Commit the rebuilt binaries along with their shader sources. Use the
[verification commands](technical-reference.md#verification) to check gameplay,
saved data and runtime behavior after source changes.
