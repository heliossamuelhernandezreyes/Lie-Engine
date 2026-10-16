# LIE 1.6: coherent visibility streams

The physical Mali-G720 MC7 comparison rejected 1.5 pages: light-position total
GPU p50 59.448389 ms OFF versus 184.630162 ms ON; visibility alone 43.857310
versus 168.901547 ms. Warm-up reproduced the regression. Camera totals were
64.494079/64.476155 ms; power 20.763079/21.719846 ms. The paired scene had
1080 internal pixels, two lights, yaw -52.655622406005804, elevation
-7.3502966033088075, distance 0.6 and energy-radius enabled. This is evidence
against that implementation, not a diagnosis of a specific hardware counter.

1.6 stages from actual 1.4, excludes 1.5 page assets/kernels and starts in the
original reference mode. Projection, rasterization, recovery, material/light
equations, original source disks and immutable capture bank remain unchanged.
The experimental `visibility_stream` control selects the new execution path;
the comparison exercises both actual binaries without changing quality.

## Work reduction and scheduling

An immutable Morton-order permutation groups each instance's receiver IDs by
local source position. It is compiled from the verified source-reference bank
and declared job levels. Every original projection ID occurs exactly once in
each level; no visible receiver, source primitive or shadow ray is subsampled.
The packet is 3,088,388 bytes and is leased once per device/hash. It is scheduling
data, not new geometry or an opaque spatial envelope.

The GPU marks unique final pixel winners, then compacts them in spatial blocks
with a 64-lane prefix scan and one global append per nonempty block. This queue
is retained across lighting-only updates. Within each physical light, a small
preparation kernel resolves persistent cache hits, backfacing receivers,
disabled sources and exact blocking witnesses. Only unresolved original IDs
enter a separate indirect-dispatch queue for exact BLAS traversal. The traversal
binary contains neither the cache-hit path nor the witness test. Per-light
dispatch barriers prevent races on packed visibility words. Existing per-light
invalidation and exact disk intersection equations remain authoritative.

The private trace queue is 3,000,016 bytes. The combined extra requested storage
is 6,088,404 bytes. This does not measure driver program memory, VRAM or process
PSS. Generic explicit identity/lease contracts are preserved for other assets;
the wall adapter supplies the current job levels and scene assembly.

## Measurement contract

`Comparar GPU` alternates reference/stream over three rounds with the same
scene and event sequence: 54 measured events (nine per mode/kind), 60 separately
retained warm-up events and exact state restoration. Initial geometry and every
camera/power/position entry point are warmed before measurement. No measured
outliers are removed. Queue preparation and all additional passes are timed,
not hidden from the GPU sum. The full scene, raw serials and per-stage evidence
are persisted in `user://lie-visibility-stream-last.json`.

After timing, three separately instrumented light-position events expose
eligible receivers, cache hits, culls, witness hits, unresolved rays, TLAS nodes,
BLAS nodes and exact disk tests. Each explicit diagnostic reads only 32 counter
bytes on the render thread. These reads and instrumentation do not occur inside
the timed comparison. Their results enter the copied report. Display FPS still
includes cached frames and must not be presented as fresh-image solve rate.

The reference remains the default until physical device measurements establish
a benefit. If source hierarchy, active queue or split kernels are unavailable,
the effect retains the accepted reference route. No frame dropping, delayed
shadow updates, reduced resolution or changed image-quality rules are introduced.

## Research and limits

The code audit found that 1.4 already uses stackless escape-index BVH traversal;
removing a nonexistent traversal stack would not address this bottleneck.
The work-order hypothesis follows the primary-source discussion of execution
and data divergence in [Tero Karras, Thinking Parallel II](https://developer.nvidia.com/blog/thinking-parallel-part-ii-tree-traversal-gpu/).
Its reported NVIDIA timings are not predictions for Mali or this engine.
[Arm's Mali Offline Compiler](https://developer.arm.com/tools-and-software/mali-offline-compiler)
can report register and stack use, but an actual G720 compiler report is not
available here; register pressure/spilling therefore remain unmeasured.
Splitting and ordering are hypotheses requiring paired device timing, not
guaranteed speedups. Software Vulkan correctness cannot establish Mali speed.

Before delivery require deterministic/permutation regressions, changed shader
and command checks, CPU rig/agent checks, actual Vulkan queue boundary/ownership
tests, real-bank images/depth/cache/light/resize tests, actual 1.4 regressions
and a signed APK whose bank and order packet hashes match their manifests.
