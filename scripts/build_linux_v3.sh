#!/bin/sh
# Bootstrap V for the Linux setup on a machine that has no V compiler yet.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "${1:-}" in
    -h|--help) echo "Usage: $0"; exit 0 ;;
esac
if [ "$#" -ne 0 ]; then
    echo "Usage: $0" >&2
    exit 2
fi
if command -v v >/dev/null 2>&1; then
    exec v run "$project_dir/scripts/build_linux_v3.vsh"
fi

bootstrap_version=0.5.2
case $(uname -m) in
    x86_64) asset=v_linux.zip; checksum=86caf9e70c3342d48ef19eb4f6c47b709f18c90ae86255520d5c29df6b482e23 ;;
    aarch64) asset=v_linux_arm64.zip; checksum=7e102f0ecc722bc59fea83ab1c99ae49c2f7be8f30abee9443220e452a439ed3 ;;
    *) echo 'Install V 0.5.2 or newer and add v to PATH.' >&2; exit 1 ;;
esac
cache="${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3"
bootstrap="$cache/bootstrap-$bootstrap_version-${asset%.zip}"
if [ ! -x "$bootstrap/v" ]; then
    for tool in curl unzip sha256sum; do
        command -v "$tool" >/dev/null 2>&1 || {
            echo "Install V or add $tool to PATH to bootstrap the pinned release." >&2
            exit 1
        }
    done
    mkdir -p -- "$cache"
    stage=$(mktemp -d "$cache/.bootstrap.XXXXXXXX")
    trap 'find "$stage" -depth -delete' EXIT HUP INT TERM
    curl --fail --location --retry 3         "https://github.com/vlang/v/releases/download/$bootstrap_version/$asset"         --output "$stage/$asset"
    printf '%s  %s\n' "$checksum" "$stage/$asset" | sha256sum --check --status
    unzip -q "$stage/$asset" -d "$stage"
    [ -x "$stage/v/v" ]
    mv -T -- "$stage/v" "$bootstrap" || [ -x "$bootstrap/v" ]
    find "$stage" -depth -delete
    trap - EXIT HUP INT TERM
fi
exec "$bootstrap/v" run "$project_dir/scripts/build_linux_v3.vsh"
