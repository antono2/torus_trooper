#!/usr/bin/env bash
# Run on an isolated display, e.g. xvfb-run -a bash scripts/test_replay_ui.sh.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary=$(realpath -- "${1:-$project_dir/torus_trooper}")
for dependency in xdotool python3; do command -v "$dependency" >/dev/null; done
test_dir=$(mktemp -d)
game_pid=''
cleanup() {
    status=$?
    if [[ "$status" != 0 && -f "$test_dir/game.log" ]]; then cat "$test_dir/game.log" >&2; fi
    if [[ -n "$game_pid" ]]; then
        kill -TERM "$game_pid" 2>/dev/null || true
        wait "$game_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
cd -- "$project_dir"
"$binary" --no-sound --volume 0 --res 1280 720 \
    --data-file "$test_dir/player.json" >"$test_dir/game.log" 2>&1 &
game_pid=$!
for attempt in {1..120}; do
    if ! kill -0 "$game_pid" 2>/dev/null; then cat "$test_dir/game.log"; exit 1; fi
    if grep -Fq 'Renderer bootstrap complete' "$test_dir/game.log"; then break; fi
    sleep 0.5
done
grep -Fq 'Renderer bootstrap complete' "$test_dir/game.log"
window=$(xdotool search --onlyvisible --name '^Torus Trooper' | head -1)
press() {
    xdotool keydown --window "$window" "$1"
    sleep 0.30
    xdotool keyup --window "$window" "$1"
    sleep 0.50
}
screenshot() {
    if [[ -n "${TT_REPLAY_SCREENSHOTS:-}" ]]; then
        mkdir -p -- "$TT_REPLAY_SCREENSHOTS"
        import -window "$window" "$TT_REPLAY_SCREENSHOTS/$1.png"
    fi
}
sleep 3
xdotool keydown --window "$window" Return
for attempt in {1..40}; do
    if grep -Fq 'Run started:' "$test_dir/game.log"; then break; fi
    sleep 0.25
done
xdotool keyup --window "$window" Return
grep -Fq 'Run started:' "$test_dir/game.log"
sleep 2
press Escape
for step in {1..4}; do press Down; done
screenshot title-screen
press Return
screenshot replay-library
press r
press ctrl+a
xdotool type --window "$window" --delay 80 'First flight'
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
xdotool type --window "$window" --delay 30 "$replay"
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
printf '%s\n' 'Replay UI passed: save, rename, export, import, sort, playback, remove, back.'
