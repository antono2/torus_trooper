#!/usr/bin/env bash
# Builds the Linux game with the selected V3 toolchain and native dependencies.
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
toolchain_dir=${TT_V3_TOOLCHAIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3/c0449e860641}
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

# Separate module caches when manifest pins change, retaining the compiler.
modules_key=$(git hash-object "$project_dir/v.mod")
modules_dir=$toolchain_dir/modules-$modules_key

mkdir -p "$toolchain_dir"

clone_pinned() {
    local url=$1 ref=$2 destination=$3
    if [[ -d "$destination/.git" ]]; then
        if [[ $(git -C "$destination" rev-parse HEAD) != "$(git -C "$destination" rev-parse --verify "$ref^{commit}" 2>/dev/null)" ]]; then
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

clone_pinned https://github.com/vlang/v.git \
    c0449e86064168aabb4c6c4505c5b5b5ad4fdbc1 "$v_dir"
clone_pinned https://github.com/vlang/vc.git \
    8af812feb76c678abd86a8e682fd9ab2790e519c "$v_dir/vc"

clone_pinned https://github.com/vlang/tccbin.git \
    d6e7ac1b1bcc98aed734a6ecbfa8509f24606c74 "$v_dir/thirdparty/tcc"
if [[ ! -x "$v_dir/v" ]]; then
    make -C "$v_dir" local=1
fi

# Match CI's public dependency revisions without changing ~/.vmodules or
# requiring another V compiler to install this compiler's dependencies.
module_tag() {
    awk -F "'" -v module="$1" '
        index($2, module "@") == 1 {
            sub(/^[^@]+@/, "", $2)
            print $2
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$project_dir/v.mod"
}

clone_pinned https://github.com/antono2/vulkan.git \
    "$(module_tag antono2.vulkan)" "$modules_dir/antono2/vulkan"
clone_pinned https://github.com/antono2/opencl.git \
    "$(module_tag antono2.opencl)" "$modules_dir/antono2/opencl"
clone_pinned https://github.com/antono2/vulkan_memory_allocator.git \
    "$(module_tag antono2.vkmemalloc)" "$modules_dir/antono2/vkmemalloc"
clone_pinned https://github.com/antono2/memory.git \
    v1.4.0 "$modules_dir/antono2/memory"

export VMODULES=$modules_dir
export VULKAN_SDK=$headers_dir
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
cd -- "$project_dir"
"$v_dir/v" -cc gcc -o torus_trooper .
echo "Built $project_dir/torus_trooper with pinned V3 and Vulkan headers."
echo 'Run silently with: ./torus_trooper --no-sound --volume 0'
