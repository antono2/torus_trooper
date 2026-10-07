#!/usr/bin/env bash
# Runs repository verification gates for the game, supporting libraries, shaders, and tooling.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
binary="$build_dir/torus_trooper"

cd "$repo_dir"

python3 scripts/check_guide_links.py

for removed_legacy_path in game util/gl util/usdl thirdparty/glad \
	.gitmodules submodule thirdparty/bulletml; do
	if [[ -e "$removed_legacy_path" ]]; then
		printf 'inactive legacy path returned: %s\n' "$removed_legacy_path" >&2
		exit 1
	fi
done

if grep -REni '\b(sdl|sdl2|vgl)\b|#flag.*-l(gl|opengl)([[:space:]]|$)' \
		v.mod torus_trooper.v runtime sim; then
	printf '%s\n' 'SDL, VGL, or OpenGL returned to the active source graph' >&2
	exit 1
fi

python3 scripts/check_compiler_diagnostics.py -- v -cc gcc test torus_trooper_test.v
python3 scripts/check_compiler_diagnostics.py -- v -cc gcc test font5x7 sim runtime
python3 scripts/check_compiler_diagnostics.py -- v -cc gcc -o "$binary" .

linked_libraries=$(ldd "$binary")
if grep -Eiq 'libSDL|libOpenGL|libGL(X|\.)' <<<"$linked_libraries"; then
	printf '%s\n' 'SDL or OpenGL returned to the native runtime linkage' >&2
	printf '%s\n' "$linked_libraries" >&2
	exit 1
fi

headless_output=$($binary --headless --ticks 600 --no-sound --volume 0)
printf '%s\n' "$headless_output"
# These checksums include raw f32 bits. V3 changes a few low-order floating
# bits relative to V1; the discrete counts and render checksum stay the same.
grep -Fq 'checksum=490efd84cf12692f' <<<"$headless_output"
grep -Fq 'render_instances=180' <<<"$headless_output"
grep -Fq 'render_checksum=c24e7880e15b4f35' <<<"$headless_output"
grep -Fq 'course_vertices=9152' <<<"$headless_output"
grep -Fq 'course_checksum=e1b047594b88bcb3' <<<"$headless_output"
grep -Fq 'course_fill_vertices=10560' <<<"$headless_output"
grep -Fq 'course_fill_checksum=de699b72a44f7744' <<<"$headless_output"
grep -Fq 'course_backward_vertices=9152' <<<"$headless_output"
grep -Fq 'course_backward_checksum=9f0a33dc89dd13eb' <<<"$headless_output"
grep -Fq 'course_backward_fill_vertices=10368' <<<"$headless_output"
grep -Fq 'course_backward_fill_checksum=cf2b2d1d58c1a64b' <<<"$headless_output"
grep -Fq 'compute_checksum=3df697f628fcafc9' <<<"$headless_output"

fallback_output=$($binary --headless --ticks 600 --compute opencl --no-sound --volume 0)
grep -Fq 'checksum=490efd84cf12692f' <<<"$fallback_output"
grep -Fq 'compute_requested=opencl' <<<"$fallback_output"
grep -Fq 'compute_active=cpu' <<<"$fallback_output"
grep -Eq 'compute_fallback_batches=[1-9][0-9]*' <<<"$fallback_output"
grep -Fq 'compute_checksum=3df697f628fcafc9' <<<"$fallback_output"

if [[ "${TT_OPENCL_SMOKE:-0}" == "1" ]]; then
	opencl_binary="$build_dir/torus_trooper_opencl"
	python3 scripts/check_compiler_diagnostics.py -- v -d opencl_compute -cc gcc -o "$opencl_binary" .
	opencl_output=$($opencl_binary --headless --ticks 600 --compute opencl --no-sound --volume 0)
	printf '%s\n' "$opencl_output"
	grep -Fq 'checksum=490efd84cf12692f' <<<"$opencl_output"
	grep -Fq 'compute_active=opencl' <<<"$opencl_output"
	grep -Eq 'compute_verified_batches=[1-9][0-9]*' <<<"$opencl_output"
	opencl_fallback_batches=$(sed -n 's/^compute_fallback_batches=//p' <<<"$opencl_output")
	opencl_mismatched_batches=$(sed -n 's/^compute_mismatched_batches=//p' <<<"$opencl_output")
	opencl_bullet_mismatched_batches=$(sed -n 's/^compute_bullet_mismatched_batches=//p' <<<"$opencl_output")
	[[ "$opencl_fallback_batches" == "$opencl_mismatched_batches" ]]
	[[ "$opencl_mismatched_batches" == "$opencl_bullet_mismatched_batches" ]]
	grep -Fq 'compute_particle_mismatched_batches=0' <<<"$opencl_output"
	grep -Fq 'compute_shot_mismatched_batches=0' <<<"$opencl_output"
	grep -Fq 'compute_enemy_mismatched_batches=0' <<<"$opencl_output"
	grep -Fq 'compute_checksum=3df697f628fcafc9' <<<"$opencl_output"
fi

probe_output=$("$binary" --no-sound --volume 0 --res 800 600 --reverse --brightness 70 --luminosity 40 --probe)
printf '%s\n' "$probe_output"
grep -Eq 'Vulkan allocator: blocks=[1-9][0-9]* allocations=3' <<<"$probe_output"

# Exercise the documented default command as well as the explicit GCC binary.
# Keep the documented launcher under the same strict V3 toolchain as CI.
default_run_output=$(v run . --no-sound --volume 0 --res 800 600 --probe)
grep -Fq 'GLFW: Vulkan surface creation succeeded' <<<"$default_run_output"
grep -Eq 'Vulkan allocator: blocks=[1-9][0-9]* allocations=3' <<<"$default_run_output"

set +e
invalid_resolution_output=$("$binary" --no-sound --res 0 600 --probe 2>&1)
invalid_resolution_status=$?
set -e
if [[ $invalid_resolution_status -ne 2 ]]; then
	printf 'invalid resolution unexpectedly returned %s\n' "$invalid_resolution_status" >&2
	exit 1
fi
grep -Fq 'resolution width and height must be positive' <<<"$invalid_resolution_output"

if [[ "${TT_VISUAL_SMOKE:-0}" == "1" ]]; then
	set +e
	timeout --signal=INT --kill-after=3s 16s "$binary" --no-sound --volume 0 --test-effects
	status=$?
	set -e
	if [[ $status -ne 0 && $status -ne 124 ]]; then
		exit "$status"
	fi
	tuning_output=$("$binary" --no-sound --volume 0 --res 1000 700 \
		--test-object-tuning --data-file "$build_dir/tuning-player.json" \
		--object-sizes-file "$build_dir/object-sizes.json")
	grep -Fq 'TUNE opened.' <<<"$tuning_output"
	grep -Fq 'simulation ticks=0' <<<"$tuning_output"
fi

if [[ "${TT_REPLAY_UI_SMOKE:-0}" == "1" ]]; then
    bash scripts/test_replay_ui.sh "$binary"
fi
