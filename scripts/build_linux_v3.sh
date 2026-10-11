#!/usr/bin/env bash
# Builds the Linux game with the selected V3 toolchain and native dependencies.
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for command in git make gcc python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing $command. Install the Linux build prerequisites first." >&2
        exit 1
    fi
done
python3 "$project_dir/scripts/compatibility.py" --platform linux >/dev/null
pin() { python3 "$project_dir/scripts/compatibility.py" --platform linux --get "$1"; }
v_commit=$(pin v)
vc_commit=$(pin vc)
tcc_commit=$(pin tcc)
headers_commit=$(pin headers)
memory_tag=$(pin module_memory)
compatibility_key=$(sha256sum "$project_dir/compatibility.json" | cut -c1-12)
toolchain_dir=${TT_V3_TOOLCHAIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/torus-trooper-v3/$compatibility_key}
v_dir=$toolchain_dir/v
headers_dir=$toolchain_dir/Vulkan-Headers
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
    "$headers_commit" "$headers_dir"

clone_pinned https://github.com/vlang/v.git \
    "$v_commit" "$v_dir"
clone_pinned https://github.com/vlang/vc.git \
    "$vc_commit" "$v_dir/vc"

clone_pinned https://github.com/vlang/tccbin.git \
    "$tcc_commit" "$v_dir/thirdparty/tcc"
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
    "$memory_tag" "$modules_dir/antono2/memory"

export VMODULES=$modules_dir
export VULKAN_SDK=$headers_dir
export V_MACOS_V3_NO_FALLBACK=1
export V_C_ERROR_BUG_REPORT_DISABLED=1
cd -- "$project_dir"
python3 scripts/compatibility.py --platform linux --modules "$modules_dir"
"$v_dir/v" run scripts/check_installed_deps.vsh
"$v_dir/v" -cc gcc -o torus_trooper .
echo "Built $project_dir/torus_trooper with pinned V3 and Vulkan headers."
echo 'Run silently with: ./torus_trooper --no-sound --volume 0'
