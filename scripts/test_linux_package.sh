#!/usr/bin/env bash
# Run inside xvfb-run. Hide host copies of every bundled library in a private
# mount namespace, so this cannot accidentally pass using installed GLFW.
set -euo pipefail
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
tar -xzf "${1:?Usage: test_linux_package.sh ARCHIVE}" -C "$test_dir"
package="$test_dir/torus-trooper"
python3 - "$package" > "$test_dir/host-libraries.txt" <<'PY'
import json, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
cache = subprocess.check_output(['/sbin/ldconfig', '-p'], text=True)
for row in json.loads((root/'thirdparty/linux-runtime/libraries.json').read_text()):
    for line in cache.splitlines():
        if line.strip().startswith(row['library']+' ') and 'x86-64' in line:
            print(Path(line.split(' => ')[1]).resolve())
            break
    else:
        raise RuntimeError('Host library missing from test fixture: '+row['library'])
PY
mapfile -t paths < "$test_dir/host-libraries.txt"
namespace=(bwrap --ro-bind / / --dev-bind /dev /dev --proc /proc --chdir "$package")
for path in "${paths[@]}"; do namespace+=(--ro-bind /dev/null "$path"); done
cp "$package/torus_trooper" "$test_dir/unbundled"
if "${namespace[@]}" "$test_dir/unbundled" --headless --ticks 1 > "$test_dir/bare.log" 2>&1; then
    echo 'Test fixture failed: bare binary still found the hidden system libraries' >&2
    exit 1
fi
grep -Fq 'libglfw.so.3' "$test_dir/bare.log"
"${namespace[@]}" ./torus_trooper --headless --ticks 600 --no-sound --volume 0 > "$test_dir/headless.log"
grep -Fq 'checksum=490efd84cf12692f' "$test_dir/headless.log"
"${namespace[@]}" ./play.sh --probe --no-sound --volume 0 --data-file "$test_dir/player.json" > "$test_dir/probe.log" 2>&1
grep -Fq 'GLFW: Vulkan surface creation succeeded' "$test_dir/probe.log"
printf '%s\n' 'Linux package passed with all bundled libraries hidden on the host.'
