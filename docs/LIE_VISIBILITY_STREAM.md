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
with a portable 64-lane bit mask and one global append per nonempty block. This queue
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

Preparation/traversal use separate production and instrumented Vulkan pipeline
specializations. Per-node/disk diagnostic counter branches are compile-time
false in production. The portable ballot uses two shared 32-bit masks, population
counts and three barriers, replacing the initial thirteen-barrier prefix scan.
No optional native subgroup feature or unexposed Godot device capability is
assumed. This trades shared atomic OR operations for fewer barriers and must
still be measured on the target GPU.

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

## Accepted runtime and measured result

Runtime `df7b9beced441219d23dfa188d9784fbdc018d01`, native/export run
38841998377, job 116783980652, artifact 12021253367. All 19 triggered workflows
passed. Local checks: three Python tests, five compiled SPIR-V shaders, 13
commands, two standalone test parse checks, CPU rig 247 and agent 25. Actual
Vulkan checks: queue 54, new Mobile 64, prior 1.4 Mobile 73 and exact witness
oracle 281. The work-counter checks exercise the instrumented specializations;
the timed comparison uses the production specializations.

Initial shipping output and all four tested camera views match 1.4 exactly in
RGB and coverage, with exact tested depth. Three moved-light comparisons have
zero RGB error and the 0.01-degree comparison has maximum RGB difference
2.099e-7, within the 1e-4 acceptance threshold. Area/LOD/continuity/resize and
inactive-queue fallback comparisons also match. This is tested rendering
equivalence, not a new photometric-realism claim.

The final 1080, two-light **software Vulkan (llvmpipe)** paired totals are:

| Change | Reference p50 | Stream p50 | Reference p95 | Stream p95 |
| --- | ---: | ---: | ---: | ---: |
| Camera | 230.566 ms | 231.202 ms | 250.631 ms | 239.609 ms |
| Light power | 76.080 ms | 78.125 ms | 102.730 ms | 86.074 ms |
| Light position | 206.807 ms | 171.223 ms | 220.528 ms | 187.630 ms |

Light-position total median improves by 17.21%. Camera median is 0.28% higher
and light-power median 2.69% higher. The negatives remain in the evidence;
this is not a uniform win and not a physical Mali measurement. Nine measured
events per mode/kind, all 54 measured events, 60 separately classified warm-up
events and 1,356 raw timestamp rows were retained with exact state restoration.
The compact report, scene and three counter events fit below 16 KiB.

The three untimed work observations report 161,746 receiver/light pairs each,
including 80,873 cached pairs for the unchanged source. Only 61,562 / 25,560 /
46,456 unresolved pairs enter BLAS traversal at the three tested key positions.
This confirms classification and quantifies remaining work; it does not claim
that the old kernel traced cached pairs. The highest observed event visits
5,882,565 BLAS nodes and tests 3,560,783 disks. Counters are from the separate
instrumented solves, not added to the timing samples.

The earlier accepted initial implementation (`24f80c1`, run 38840927767) is
also preserved in full. It improved moved-light software median by 6.27%, but
camera/power regressed by 5.50%/6.96%. Its scan and per-node diagnostics were
then revised. The full initial append has fourteen barriers including its final
base synchronization (thirteen in the prefix phase). Do not compare absolute
times across these separate CI runners; only compare variants paired inside
each run. The first test-script parser failure is retained separately.

## Signed APK and evidence

`LIE-Visibilidad-1.6.0.apk`: 59,883,176 bytes, package
`org.lieengine.wallruntime.v160`, code 16, SHA-256
`738b8bb7aaf2f427d40601500ca80cf289cb7da9f4e00fc7efe5c86e1fe5f8fa`.
Official Godot 4.7.2 Android template verified, APK aligned, signed and checked.
Downloaded artifact ZIP SHA-256:
`2a6f55ff07013ba6f0b6afc208b8873f588e4444c39a7fe63a10d3b6c722d852`.
APK bank and order bytes match their manifests; deprecated 1.5 page data/shaders
are absent. Requested appearance storage is 286,669,404 bytes; extra driver
pipeline memory is not measured. Bank uploads, one collider, independent order
leases, cached idle and retained allocations passed.

Full initial/final native observations, queue/local checks and artifact
identities are in `docs/checkpoints/LIE_VISIBILITY_STREAM_*.json`. The supplied
Mali page regression remains in `LIE_SPATIAL_PAGE_MALI_NEGATIVE.json`. Capture
banks and APK bytes are outside Git. The app keeps reference mode as default;
use `Comparar GPU` then `Informe` / `Copiar informe` on the physical Mali before
choosing the new route. No maximum or sustained phone FPS is established here.
