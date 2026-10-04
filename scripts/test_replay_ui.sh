#!/usr/bin/env bash
# Run on an isolated display, e.g. xvfb-run -a bash scripts/test_replay_ui.sh.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary=$(realpath -- "${1:-$project_dir/torus_trooper}")
for dependency in xdotool xprop stdbuf python3; do command -v "$dependency" >/dev/null; done
test_dir=$(mktemp -d)
game_pid=''
frame_pid=''
cleanup() {
    status=$?
    if [[ "$status" != 0 && -f "$test_dir/game.log" ]]; then cat "$test_dir/game.log" >&2; fi
    if [[ -n "$frame_pid" ]]; then
        kill -TERM "$frame_pid" 2>/dev/null || true
        wait "$frame_pid" 2>/dev/null || true
    fi
    if [[ -n "$game_pid" ]]; then
        kill -TERM "$game_pid" 2>/dev/null || true
        wait "$game_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
cd -- "$project_dir"
# This checks replay interaction, while check.sh separately probes the default
# renderer. Keep software Vulkan responsive enough to sample held UI keys.
printf '%s\n' '{"version":14,"antialiasing_samples":1,"near_blur_percent":0,"track_draw_distance":16,"wire_draw_distance":16,"border_draw_distance":16}' > "$test_dir/player.json"
"$binary" --no-sound --volume 0 --res 640 360 \
    --data-file "$test_dir/player.json" >"$test_dir/game.log" 2>&1 &
game_pid=$!
for attempt in {1..120}; do
    if ! kill -0 "$game_pid" 2>/dev/null; then cat "$test_dir/game.log"; exit 1; fi
    if grep -Fq 'Renderer bootstrap complete' "$test_dir/game.log"; then break; fi
    sleep 0.5
done
grep -Fq 'Renderer bootstrap complete' "$test_dir/game.log"
window=$(xdotool search --onlyvisible --name '^Torus Trooper' | head -1)
# Use XTest keyboard input so modifier state matches real keyboard events.
xdotool windowfocus --sync "$window"
# The runtime writes the window title each menu/playback frame. Property events
# acknowledge processed frames even when the text itself has not changed.
: > "$test_dir/frames.log"
stdbuf -oL xprop -spy -id "$window" _NET_WM_NAME > "$test_dir/frames.log" &
frame_pid=$!
wait_frames() {
    local target=$1
    for attempt in {1..120}; do
        kill -0 "$game_pid" 2>/dev/null || return 1
        if [[ $(wc -l < "$test_dir/frames.log") -ge "$target" ]]; then return; fi
        sleep 0.25
    done
    printf 'Timed out waiting for rendered input frames\n' >&2
    return 1
}
wait_frames 1
press() {
    local before
    before=$(wc -l < "$test_dir/frames.log")
    case "$1" in
        ctrl+*|r|e|i|p|s|y|Delete)
            # Library commands are queued callbacks. Holding a letter could
            # repeat it into the text field that the command just opened.
            xdotool key --clearmodifiers "$1"
            wait_frames "$((before + 2))"
            return
            ;;
    esac
    xdotool keydown "$1"
    wait_frames "$((before + 2))"
    before=$(wc -l < "$test_dir/frames.log")
    xdotool keyup "$1"
    wait_frames "$((before + 2))"
}
screenshot() {
    if [[ -n "${TT_REPLAY_SCREENSHOTS:-}" ]]; then
        mkdir -p -- "$TT_REPLAY_SCREENSHOTS"
        import -window "$window" "$TT_REPLAY_SCREENSHOTS/$1.png"
    fi
}
sleep 3
xdotool keydown Return
for attempt in {1..40}; do
    if grep -Fq 'Run started:' "$test_dir/game.log"; then break; fi
    sleep 0.25
done
xdotool keyup Return
grep -Fq 'Run started:' "$test_dir/game.log"
# Software Vulkan can take several seconds per frame. Wait for the gameplay
# timer to advance before suspending; a fixed sleep can record zero inputs.
for attempt in {1..120}; do
    if xdotool getwindowname "$window" | grep -Eq 'TIME (1:|0:)'; then break; fi
    sleep 0.25
done
xdotool getwindowname "$window" | grep -Eq 'TIME (1:|0:)'
press Escape
# Nested menus close before keyboard Escape resumes the exact suspended state.
screenshot suspended-start-menu
for step in {1..3}; do press Down; done
screenshot selected-settings-menu
press Return
screenshot selected-setting
press Escape
grep -Fq 'Settings closed.' "$test_dir/game.log"
kill -0 "$game_pid"
press Escape
python3 - "$test_dir/game.log" <<'PY_RESUME'
from pathlib import Path
import re, sys
log = Path(sys.argv[1]).read_text()
suspended = re.search(r'Run suspended: (ticks=\d+ score=\d+ checksum=[0-9a-f]+)', log)
resumed = re.search(r'Run resumed: (ticks=\d+ score=\d+ checksum=[0-9a-f]+)', log)
assert suspended and resumed, log
assert suspended[1] == resumed[1], (suspended[1], resumed[1])
assert log.count('Run started:') == 1, log
PY_RESUME
kill -0 "$game_pid"
press Escape
# Starting another run commits the suspended recording to the library.
xdotool keydown Return
for attempt in {1..120}; do
    if [[ $(grep -Fc 'Run started:' "$test_dir/game.log") -ge 2 ]]; then break; fi
    sleep 0.25
done
xdotool keyup Return
sleep 0.5
test "$(grep -Fc 'Run started:' "$test_dir/game.log")" -ge 2
press Escape
for step in {1..4}; do press Down; done
screenshot title-screen
press Return
screenshot replay-library
press r
press ctrl+a
xdotool type --delay 80 'First flight'
press Return
screenshot replay-library
press e
press Return
replay=$(python3 - "$test_dir" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
data = json.loads((root / 'player.json').read_text())
assert len(data['replays']) == 1, data
assert data['replays'][0]['name'] == 'First flight', data
files = list((root / 'replays').glob('*.ttr'))
assert len(files) == 1, files
assert json.loads(files[0].read_text())['replay']['inputs'] == data['replays'][0]['inputs']
print(files[0])
PY
)
press i
screenshot file-browser
press p
press ctrl+a
xdotool type --delay 30 "$replay"
press Return
screenshot imported-replay
python3 - "$test_dir/player.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert len(data['replays']) == 2, data
assert data['replays'][0] == data['replays'][1]
assert data['high_scores'][0] == data['replays'][0]['score']
PY
press s
press Return
sleep 1
screenshot replay-playback
press Escape
# Leaving playback must neither quit nor start a live run from held input.
kill -0 "$game_pid"
screenshot back-to-library
press Delete
press y
python3 - "$test_dir/player.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert len(data['replays']) == 1, data
PY
press Escape
kill -0 "$game_pid"
if grep -Fq 'Validation Error' "$test_dir/game.log"; then
    cat "$test_dir/game.log" >&2
    exit 1
fi
if [[ -n "${TT_REPLAY_SCREENSHOTS:-}" ]]; then
    cp "$test_dir/game.log" "$TT_REPLAY_SCREENSHOTS/game.log"
fi
printf '%s\n' 'Replay UI passed: keyboard menu/resume, save, rename, export, import, sort, playback, remove, back.'
