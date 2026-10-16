# LIE 1.7: tighter bounds for the same captured disks

## Physical 1.6 result

The supplied 2412DPC0AG / Mali-G720 MC7 report contains 54 measured events,
60 separately retained warm-up events and exact state restoration. Nine
samples per mode/kind, uncontrolled thermals, same 1080 two-light scene:

| Event | Actual 1.4 p50 | Stream 1.6 p50 | Change in time |
| --- | ---: | ---: | ---: |
| Camera | 52.307156 ms | 51.494156 ms | -1.55% |
| Light power | 18.737462 ms | 18.350231 ms | -2.07% |
| Light position | 42.237080 ms | 42.609387 ms | +0.88% |

This does not establish a material median speedup. The software-Vulkan
17.21% moved-light improvement did not transfer to this physical scene.
P95 values improved in this run, but nine events and uncontrolled thermals
do not establish sustained tail-latency improvement. The restored final
`visibility_stream=false` is expected; both modes were measured. Display
55 FPS includes cached images and is not the rate of new lighting solves.
Do not compare these absolute values with other versions' different scenes.
The transcribed subset, exact paired scene fields and all supplied work
counters are in `checkpoints/LIE_VISIBILITY_STREAM_MALI.json`; that file is
not the missing original per-frame/timestamp history.

At key azimuth -24, 77,591 unchanged fill pairs were cached. Of the 77,591
key receivers, 71,342 (91.95%) still required traversal; only 3,643 (4.70%)
were resolved by known blockers. Those remaining rays visited 4,737,979
source-BLAS nodes and tested 2,097,575 disks. Splitting/sorting did not remove
the expensive geometric work: original visibility p50 was 30.251694 ms,
and stream trace_0 alone was 30.248386 ms, plus preparation/reset costs.

## Change under test

The original compiler bounds every tangent disk by `position +/- radius`
on all three axes, the bounds of its enclosing sphere. The new compiler
projects the actual planar circle onto each axis. For raw normal n and
radius r its axis extent is `r * sqrt(max(0, 1 - n_axis^2 / dot(n,n)))`.
The new boxes include an outward float32 guard, then are clamped to the
original conservative boxes. Internal nodes are refitted bottom-up.

Node indices, escape links, primitive IDs, leaf lists, traversal order,
instance hierarchy, original bank, disk intersection/shadow equations,
resolution, material and recovery kernels are unchanged. Runtime original
1.4 stage-11 binaries bind either original or refitted node data. Stream
scheduling is OFF in both timed modes, isolating the bound-data change.
Optional legacy/monolithic or unsupported-device paths retain the original
bounds. The startup default remains the actual reference until phone timing.

The immutable refitted node packet is 4,194,240 bytes for this bank, shared
by device/hash leases without duplicating leaves. Descriptor sets for both
routes are created before timing and retained across scene updates. This
requested allocation is not measured physical VRAM/PSS or driver program
memory. Persistent geometry identity remains the original exact disk scene;
switching bounds invalidates visibility and private hints for comparisons.

The compiler accepts generic 80-byte source banks with original binary BVH
packets; the wall is its current adapter. Circle containment and topology
checks do not prove floating-point equivalence for every possible future
coordinate scale/affine transform. Every new asset still requires the common
native depth/coverage/material acceptance, especially grazing rays and extreme
transforms. The numerical guard is explicitly not a universal error proof.

The primary-source [pbrt disk discussion](https://www.pbr-book.org/4ed/Shapes/Disks)
describes planar disk bounds and plane-then-radius intersection. Our arbitrary
normal axis extents are derived from circle projection; pbrt does not supply
a performance prediction for this engine or Mali hardware.

## Measurement and acceptance

The offline probe selects 1,200 original source IDs with a fixed seed before
observing results, launches only front-facing rays toward a declared fixed
local light, and compares original/refitted BLAS work using float64 disk
intersection. It tests one master without TLAS, Vulkan or Android timing.
`tools/lie_tangent_probe.py` reproduces it; its checkpoint is retained. This
is an initial work hypothesis, not a physical FPS result.

The new `Comparar GPU` retains 54 measured events and 60 warm-up events with
alternating original/refitted order and exact state restoration. Timed events
have no GPU reads. After timing, six separate work events compare both node
packets through the identical instrumented stream binary, three lights per
packet. Each reads 32 counter bytes. Those counters diagnose work reduction
and are not timings of the production 1.4 execution path.

Before APK delivery require Python circle/forest/invalid-input tests, changed
GDScript command/parse checks, CPU rig/agent checks, independent exhaustive
float64/GPU fixture comparisons, real-bank original/candidate image/depth/
light/camera/options/cache/resize checks, paired actual Vulkan timing and a
verified signed APK. Native acceptance is recorded below. Physical 1.7 speed
is still pending; software measurements do not predict the Mali result.

## Accepted native run and APK

Runtime `7fcd5b0157c554cd76bc96cd46ed4d1a236b860d`, run 38849878435,
job 116808512152. All 18 triggered workflows passed. Native checks: new
real-bank laboratory 68, queue 54, prior 1.4 laboratory 73, original exact
witness oracle 281 and refitted exact witness oracle 281. Commands 13,
two standalone parse checks, four new Python tests, eight local Python
regressions, CPU rig 247 and agent 25 also passed. Initial/camera RGB and
tested depth are exact. Moved-light maximum RGB difference is 2.0984e-7 at
0.01 degrees; other tested displacements match exactly, within the 1e-4
acceptance threshold. The area/LOD/continuity/resize/queue/box comparisons
also pass. These do not establish new photometric realism.

The actual **software Vulkan, llvmpipe LLVM 20.1.2** paired totals are:

| Event | Reference p50 | Tight p50 | Reference p95 | Tight p95 |
| --- | ---: | ---: | ---: | ---: |
| Camera | 392.175750 ms | 387.773492 ms | 421.187357 ms | 406.847011 ms |
| Light power | 94.591597 ms | 97.428507 ms | 103.109917 ms | 107.857111 ms |
| Light position | 248.390892 ms | 202.979612 ms | 259.880888 ms | 214.747087 ms |

Camera total p50 improves 1.12%, power regresses 3.00%, and moved-light total
p50 improves 18.28%. Moved-light visibility stage p50 changes from 154.600155
to 109.362927 ms. Only within-run comparisons are meaningful. All 54 measured
events, 60 separately retained warm-up events and 1,050 timestamp rows were
retained with exact restoration and no outlier removal.

The separate paired work observations retain the same receiver and unresolved
ray counts. At azimuth -24, BLAS nodes change 4,740,290 -> 3,536,242 (-25.40%)
and disk tests 2,097,482 -> 635,644 (-69.69%); TLAS visits are unchanged.
Across all three work probes, BLAS work falls 25.22-25.40%, disk work
69.18-69.69%. Those are instrumented work counts, not extra production timing
samples. The copied report retains both work modes below 16 KiB.

The clean CI original node/leaf packets have distinct hashes from the packets
recovered locally from 1.6. Both use the identical immutable source bank; each
refit is bound to its own original packet hashes, and metadata/leaf topology is
unchanged within each pair. Do not infer identical acceleration-packet bytes
or directly compare timings across those builds. Final packet SHA-256 is
`b50febcba59328a401a66628e58bc3f0f63134f7d4d0e694cd976df1ef08603c`.

`LIE-Limites-1.7.0.apk`: 61,792,918 bytes, package
`org.lieengine.wallruntime.v170`, version `1.7.0-tangent-bounds`, SHA-256
`ee97373b137cae3348e948604256ef45825bfcc9260aa3d5e702d0a9504edd84`.
Official Godot 4.7.2 Android template verified, APK normalized, aligned,
signed and checked in CI. Artifact 12024911543, archive SHA-256
`a001268cd67942818efc8f81b1eda9db29f23c032971e159c6b87c7b2a5d8bff`.
Downloaded ZIP, APK, source bank and refitted node packet identities were
verified locally. Total requested appearance storage is 290,863,644 bytes,
including the 4,194,240-byte alternative node packet. This is not PSS/VRAM.

The full native observations and compact acceptance identities are preserved
in `checkpoints/LIE_TANGENT_BOUNDS_NATIVE.json` and
`checkpoints/LIE_TANGENT_BOUNDS_ACCEPTANCE.json`. APK/capture bytes remain
outside Git. The actual 1.4 route is still the startup default. On the physical
Mali, use `Comparar GPU`, then `Informe` / `Copiar informe`; the benchmark
selects both modes and restores the scene itself.
