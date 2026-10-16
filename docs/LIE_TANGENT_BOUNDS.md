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
verified signed APK. Native GPU checks and physical speed are pending at
the creation of this checkpoint; acceptance and artifact identity are appended
only after the corresponding observations exist.
