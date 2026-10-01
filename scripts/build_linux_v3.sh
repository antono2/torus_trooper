#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_dir=${TT_V3_TOOLCHAIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3}
v_dir=$toolchain_dir/v
headers_dir=$toolchain_dir/Vulkan-Headers

for command in git make gcc; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing $command. Install the Linux build prerequisites first." >&2
        exit 1
    fi
done
if [[ ! -f /usr/include/volk.h ]] && ! printf '#include <volk.h>\n' | gcc -E -x c - >/dev/null 2>&1; then
    echo 'Missing volk.h. Install libvulkan-volk-dev (or an equivalent Volk development package).' >&2
    exit 1
fi

mkdir -p "$toolchain_dir"

clone_pinned() {
    local url=$1 ref=$2 destination=$3
    if [[ -d "$destination/.git" ]]; then
        if [[ $(git -C "$destination" rev-parse HEAD) != "$ref" ]]; then
            echo "Existing checkout at $destination is not at the tested revision $ref." >&2
            exit 1
        fi
        return
    fi
    if [[ -e "$destination" ]]; then
        echo "Cannot create checkout: $destination already exists." >&2
        exit 1
    fi
    git clone --filter=blob:none --no-checkout "$url" "$destination"
    git -C "$destination" fetch --depth 1 origin "$ref"
    git -C "$destination" checkout --detach "$ref"
}

clone_pinned https://github.com/KhronosGroup/Vulkan-Headers.git \
    6802bb4733b63ed5efd3adb308a6c885ef180ea1 "$headers_dir"

if [[ ! -d "$v_dir/.git" ]]; then
    clone_pinned https://github.com/vlang/v.git \
        c9b806b294234408af3794f419439599a293a0ea "$v_dir"
    clone_pinned https://github.com/vlang/vc.git \
        21490f7811a2dd366c3daa39bef8e53c1e3e5727 "$v_dir/vc"
    git -C "$v_dir" -c user.name='Torus Trooper build' \
        -c user.email='build@example.invalid' fetch \
        https://github.com/antono2/v.git fix/v3-enum-fixed-array-fn-pointer
    if [[ $(git -C "$v_dir" rev-parse FETCH_HEAD) != 21ef431f41d2853d43c2acd7a7e295f9de55838e ]]; then
        echo 'The pending V3 compiler fix changed; refusing to apply an untested revision.' >&2
        exit 1
    fi
    git -C "$v_dir" -c user.name='Torus Trooper build' \
        -c user.email='build@example.invalid' cherry-pick FETCH_HEAD
    git -C "$v_dir" apply "$project_dir/patches/v3-enum-clone.patch"
elif ! git -C "$v_dir" apply --reverse --check \
    "$project_dir/patches/v3-enum-clone.patch" 2>/dev/null; then
    echo "The cached V3 toolchain at $v_dir is incomplete. Inspect it before retrying." >&2
    exit 1
fi

clone_pinned https://github.com/vlang/tccbin.git \
    d6e7ac1b1bcc98aed734a6ecbfa8509f24606c74 "$v_dir/thirdparty/tcc"
if [[ ! -x "$v_dir/v" ]]; then
    make -C "$v_dir" local=1
fi

export VULKAN_SDK=$headers_dir
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
cd -- "$project_dir"
"$v_dir/v" -cc gcc -o torus_trooper .
echo "Built $project_dir/torus_trooper with pinned V3 and Vulkan headers."
echo 'Run silently with: ./torus_trooper --no-sound --volume 0'
