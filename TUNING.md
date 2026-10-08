# Model tuning

Use a downloaded package or [build from source](docs/technical-reference.md#build-and-run),
then open the reference scene from the game folder:

```sh
./torus_trooper --tune --object-sizes-file ./my-object-sizes.json
```

On Windows:

```powershell
.\torus_trooper.exe --tune --object-sizes-file .\my-object-sizes.json
```

`--tune` opens an interactive, silent scene. Use `--test-object-tuning` for
an automated check that closes after 300 frames.

Tab and Shift+Tab move between labeled objects and focus the camera. Mouse or
A/D orbit, Space toggles automatic orbit and W/S move closer or farther away.
`+`/`-` resize the selected
object by 0.1; Backspace restores that object's default size. The window title
shows the selected object, its scale and whether there are unsaved edits.
Ctrl+S writes the complete size catalog. Ctrl+R reloads it from disk, so you
can edit the JSON in an external editor and see size changes without restarting.
If the file is missing or malformed, reload reports an error and leaves the
current values intact. Reload discards unsaved in-scene changes.

## Live model geometry

The optional [model file](models/tune_models.json) contains editable player,
small-enemy, middle-enemy and boss preview recipes. Each entry is disabled by
default, preserving the game's existing hull. Change one entry's `enabled` to
`true`, then edit its parts in a text editor. TUNE checks the file four times
per second and updates the preview after a valid save; Ctrl+R checks it at once.
An invalid or partially written file leaves the last good models visible and
reports the error in the terminal and window title. Use `--model-file PATH` to
experiment in a separate file.

Parts are `tapered_hull` or `round_hull` (rear-to-nose sections with positive
half-width and half-height), `wing_pair` (mirrored left/right wings) or
`spike_pair` (mirrored radial spikes). Each part has a palette `color` from
`0` to `7`. In this coordinate system, increasing `z` points toward the nose,
`x` is left/right and `y` is vertical. The checked-in file provides one
editable starting recipe per ship type. Model overrides affect the tuning
preview only; they do not change collision, exhaust or the normal game.

The same size file is used by the game. Its default location is the platform
configuration directory; pass `--object-sizes-file` to work on a separate copy.
The built-in model generation is compiled from V source, so editing V code
still requires a rebuild and relaunch. Ctrl+R reloads the model and size files,
not compiled code or shaders.
Launching directly with `--tune` makes that rebuild/preview cycle shorter.
