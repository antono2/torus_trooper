# Binding update measurements — 2026-10-14

The OpenCL 1.1.0 update improves resource handling and optional deployment.
These measurements support retaining the CPU default and the existing checked
compute path. They do not establish a performance backend crossover.

## Reproduce

Use the game's pinned dependency graph and V compiler. These commands use GCC
with the same default optimization settings as the required application build.
They intentionally disable compiler fallback. OpenCL must be available; a CPU
fallback is an error for the compute benchmark.

```sh
python3 scripts/benchmark_compute.py --v v --runs 5 --output compute-results.json
v -cc gcc -o torus_trooper .
xvfb-run -a env VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation \
  python3 scripts/benchmark_renderer.py ./torus_trooper --runs 5 \
  --seconds 3 --output renderer-results.json
xvfb-run -a env VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation \
  python3 scripts/benchmark_pipeline_cache.py ./torus_trooper --runs 5 \
  --output pipeline-cache-results.json
```

The compute harness compiles a temporary test in `sim` to exercise the game's
private kernels directly, then removes it. It launches five fresh processes.
Each process uses 25 measured particle batches after three warmups per size;
75% of pool slots are active. The CPU interval includes snapshot packing and
motion. OpenCL includes slot packing, allocation reuse, upload, mark/scan/scatter,
motion, readback and output packing. Verification is timed separately. Every
batch checks exact values and source ordering. These are particle measurements,
not bullet, collision, or full-game throughput measurements.

The program comparison uses the game's entire kernel source and creates all
17 kernels. It compares nine source builds against nine valid binary loads in
each process, with binaries already in memory. It excludes disk I/O and uses
an already initialized device. Application startup includes initial discovery,
context, queue, program and kernel creation. Neither benchmark clears the
system driver's caches or isolates the machine from other work.

## Observed OpenCL costs

Linux, NVIDIA GeForce GTX 1060 6GB, driver 580.178.04, V revision
`c0449e86064168aabb4c6c4505c5b5b5ad4fdbc1`, OpenCL 1.1.0. The values below are
medians of the five process medians. Compiler setup is outside the measurements.

| Pool slots | Active particles | CPU (µs) | OpenCL round trip (µs) | Verification (µs) |
| ---: | ---: | ---: | ---: | ---: |
| 256 | 192 | 42.56 | 103.36 | 11.22 |
| 1,024 | 768 | 172.56 | 230.60 | 43.06 |
| 4,096 | 3,072 | 627.81 | 715.52 | 207.08 |
| 16,384 | 12,288 | 2,562.61 | 2,440.44 | 913.98 |

The checked game path pays for the CPU reference, OpenCL work and verification.
Even where the raw OpenCL round trip becomes slightly shorter than the CPU
interval, the checked path adds work overall. Keep CPU authoritative and do not
remove comparison or choose a default backend from these particle-only samples.
The shared binding scan also uses O(n log n) work, so replacing the current scan
is not an established speedup.

OpenCL backend startup had a median of **76.15 ms**. Warm source build plus
kernel creation took **2.338 ms**, compared with **1.122 ms** for binary import
plus kernel creation. An application disk cache would therefore save about
1.2 ms in this configuration before filesystem costs. It is not adopted here.
Other drivers or more complex programs may justify revisiting that decision.

## Observed renderer costs

The renderer benchmark uses isolated player data and 800×600 output. It starts
Normal gameplay through the ordinary menu and exits cleanly. Vulkan validation
was enabled. Timestamp and label support were available on the same NVIDIA GPU.

Five warmed process starts had median platform initialization of **157.106 ms**,
including **2.346 ms** in the eight graphics pipeline creations. One earlier
first-use probe spent 657.949 ms in those creations; subsequent runs were much
shorter. This does not identify which driver cache caused the difference.
Warm pipeline creation accounts for about 1.5% of platform startup, but that
alone does not describe a newly named executable's first launch. A second
rebuilt executable again spent about 655 ms creating pipelines on first use.
No driver cache was deleted or disabled.

The application-cache comparison seeds a cache, then alternates five uncached
and five cached copies of the identical executable with separate, previously
unused names. It preserves ordinary driver settings and includes cache-file
loading in platform initialization. In that experiment:

| First-use executable copies | Median platform startup (ms) | Median pipeline creation (ms) |
| --- | ---: | ---: |
| No application cache | 877.786 | 722.282 |
| Valid application cache | 197.032 | 26.423 |

The cache file was 243,594 bytes. This roughly 681 ms local startup saving
justifies an application pipeline cache. It is an observation for these
first-use executable copies on this driver, not a general cold-system benchmark.
The program creates every requested pipeline normally; accepting a cache blob
is not proof that any particular pipeline hit the driver's cache.

A short title/menu plus Normal-gameplay capture produced 370 completed query
samples, with mean scene interval **0.798 ms** and post-process/HUD interval
**0.367 ms**. These are GPU command intervals that can include synchronization,
not isolated shader execution time or end-to-end frame latency. They exclude
CPU simulation, event processing and presentation. A longer, controlled capture
is needed for sustained frame time or thermal claims.

## Persistent pipeline cache

Graphical startup uses `pipelines.cache` in a `torus_trooper` folder beneath
`XDG_CACHE_HOME` (or `~/.cache`) on Linux and `LocalAppData` on Windows. Directory
creation failure disables the cache without preventing startup. An explicit
`TT_PIPELINE_CACHE_FILE` overrides that location; use an absolute filename whose
parent directory exists, or an empty value to disable caching.

The file contains an application envelope with a payload checksum, followed by
native Vulkan data. Before import, the reader checks the envelope, checksum,
size limit, native header, vendor/device IDs and pipeline cache UUID. Missing,
corrupt, stale or driver-rejected data uses an empty cache. Creation or write
failure preserves rendering without a persistent cache. The renderer serializes
cache access, writes through a process-specific temporary file, atomically
replaces the destination and destroys the cache before the device. Concurrent
processes may replace each other's compatible cache; the last successful writer
wins. The cache never decides shader inputs or gameplay state.

`test_pipeline_cache.py` checks roundtrip, truncation, payload corruption, stale
vendor/UUID, missing-parent writes, default-location reuse and blocked cache
directories under Vulkan validation. The renderer
benchmark explicitly disables the application cache so warm measurements remain
comparable. `benchmark_pipeline_cache.py` controls its own isolated cache.

## Opt-in renderer diagnostics

Set `TT_GPU_PROFILE=1` when running a graphical build. The renderer reports
platform startup, pipeline creation and completed GPU intervals on clean exit.
It adds `Scene` and `Post-process and HUD` labels when `VK_EXT_debug_utils` is
available. Unsupported timestamps or labels leave rendering available.

Each frame slot owns its query pool. Results are read after its existing fence;
only available samples are consumed. Queries are reset before recording the
next use of that slot, and elapsed ticks respect the queue family's counter
width. Query pools are destroyed before the device. Profiling is off by default.

The renderer already owns its devices and presentation resources in C. The
new Vulkan ergonomic helpers require an `OwnedDevice`; constructing an owner
around the renderer's borrowed handle would obscure ownership. This change
applies their explicit timestamp/label contracts at the existing C boundary.
It does not require a renderer migration or changing the allocator's Vulkan
3.2.2 dependency. Vulkan 3.3.0 remains available for consumers with compatible
ownership and release pins.
