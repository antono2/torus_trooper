#!/usr/bin/env bash
# Assembles the Linux distribution with game assets, runtime libraries and launch metadata.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 OUTPUT_TAR_GZ [GAME_BINARY]" >&2
    exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
archive=$1
binary=${2:-"$repo_dir/torus_trooper"}
if [[ ! -x $binary ]]; then
    echo "Build the game first; executable not found: $binary" >&2
    exit 1
fi
if [[ -e $archive ]]; then
    echo "Refusing to overwrite: $archive" >&2
    exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
package="$stage/torus-trooper"
mkdir -p "$package/thirdparty/miniaudio"
cp "$binary" "$package/torus_trooper"
cp -a "$repo_dir/shaders" "$repo_dir/sounds" "$repo_dir/models" "$repo_dir/docs" "$package/"
cp "$repo_dir/LICENSE" "$repo_dir/README.md" "$repo_dir/CHANGELOG.md" "$repo_dir/TUNING.md" "$package/"
cp "$repo_dir/thirdparty/miniaudio/LICENSE" "$package/thirdparty/miniaudio/"
python3 "$repo_dir/scripts/build_shaders.py" --output-dir "$package/shaders"
python3 "$repo_dir/scripts/bundle_linux_runtime.py" "$package" "$binary"
# Resolve the bundled libraries even when the executable is launched directly.
patchelf --force-rpath --set-rpath '$ORIGIN/lib' "$package/torus_trooper"
cat > "$package/play.sh" <<'LAUNCHER'
#!/bin/sh
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
cd -- "$package_dir" || exit 1
LD_LIBRARY_PATH="$package_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec ./torus_trooper "$@"
LAUNCHER
chmod +x "$package/play.sh" "$package/torus_trooper"
tar -C "$stage" -czf "$archive" torus-trooper
echo "Packaged $archive"
