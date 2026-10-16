# LIE 1.9: screen-owned coverage and isolated bound comparisons

The physical 1.8.1 observation is retained in
`checkpoints/LIE181_PHYSICAL_OBSERVATION.json`. All six hardware intervals
contain positive activity and three independently timestamped events. This
corroborates workload presence; clocks remain uncalibrated and counters cover
the whole GPU. Compact records do not establish a useful sustained speedup:
camera 55.02 -> 57.37 ms, power 19.40 -> 18.83 ms, light position 46.81 ->
45.69 ms. These are nine-event within-run medians, not comparisons with earlier
scenes, a statistical significance result or input-to-photon latency.

Reference camera stages called `project` and `raster` actually do more than
coordinate conversion. Both loop over covered pixels. Projection resolves
depth with atomics; raster chooses owners and atomically accumulates eight
integer material channels. Together their pass medians are 30.494848 ms in
the supplied report. The sum of individual medians is not the median total.

## Screen coverage experiment

The existing source bank, stable IDs, one invisible collider, original tangent
disks, depth function, coverage function, row clipping, source transforms,
material equations, normal filter, recovery and lighting remain in use.
There are no source mesh draws or newly captured assets.

The new path runs six compute kernels on geometry changes:

1. Clear tile counts and fill cursors.
2. Project selected source blocks using the original source schedule. Cache
   unquantized albedo/roughness and count overlapping 8x8 screen tiles.
3. Scan counts in 64-tile blocks.
4. Convert block sums into exclusive global offsets.
5. Fill exact CSR lists of original projection IDs.
6. Initialize 2,560 bytes of workgroup memory for the 64 pixels. Lanes
   distribute the original source footprints across the tile: resolve minimum
   depth, synchronize, then choose owners and accumulate the original uint
   material terms through shared-memory atomics. Synchronize and write each
   global pixel once. Empty tiles retain the original clear-pass values.

The pixel loop still atomically marks every original equal-depth source flag,
and list construction and workgroup reductions still use atomics. This is not
an atomics-free renderer. All 64 lanes participate in the reduction barriers;
out-of-screen lanes return only after them. The empty-tile branch is uniform.
Integer addition is associative modulo uint32; arbitrary list order does not
change the accepted integer accumulation. The original finite empty-depth
sentinel is retained, including uncovered pixels. Projection remains bounded
to radius <=8 pixels; its 17-pixel inclusive rectangle overlaps at most nine
8x8 tiles. The list capacity is therefore nine times the accepted maximum
source work, rather than a fixed cap per tile. Dense tiles do not drop sources.

Requested extra storage at 1080 square is 39,292,744 bytes: a worst-case
27,000,000-byte reference arena, a 12,000,000-byte full-float material cache,
291,600-byte tile table and 1,144-byte block-prefix table. At 1440 it is
39,520,432 bytes. These are requested RID sizes, not measured PSS or VRAM.
Camera changes rebuild lists; light/power/exposure updates reuse them. Resize
recreates only size-dependent tables and descriptor sets. The source bank and
capacity-bounded arenas remain resident. Lists/materials belong to a consumer;
the existing immutable bank/visibility leases retain their sharing behavior.

This exchanges contested global pixel writes for conservative list construction
and local reductions. Work is proportional to each original footprint clipped
to its tile, rather than every pixel scanning every tile reference. Lists can
duplicate source work between tiles and shared atomics/barriers have a cost.
Hardware behavior must be measured; no Mali speedup follows from software-Vulkan
correctness or timing.

## Four-mode phone comparison

`Comparar GPU` runs reference, screen tiles, tangent-disk bounds, and both.
All use the original 80-byte bank and split kernels, with stream scheduling
and compact shadows disabled in clean timing. This separates two hypotheses;
the combined mode checks interaction. Startup retains the accepted reference.

Four rounds retain 144 measured events, twelve per mode/event kind, plus 160
predefined warm-up events (initial geometry and all nine trial events before
each block). Four rotations put each mode in each block slot once. This distributes
order drift but is not a thermally controlled experiment. No sample is dropped after seeing its duration. All passes,
including tile construction, count in the instrumented GPU total. CPU command
cost excludes GPU completion and is not added to overlapping whole-frame time.

After clean timing, six separate instrumented stream work probes compare only
original/tighter bounds. The stream kernel is not the production scheduling
path. Native counter intervals separately compare reference/combined across
camera, power and moved light. Fresh readers and timestamp corroboration from
1.8.1 remain in use. These six intervals are whole-device observations, not
per-kernel hardware attribution. Frequency and GPU temperature may be absent.

Pause/cancel stops native sampling and restores scene/options. Full history,
warm-up, tails and telemetry are in `user://lie-screen-tiles-last.json` and
`user://lie-performance-last.json`. The copied report includes all four timing
summaries, per-stage medians, scene, work probes, native blocks and their units;
per-stage tails stay in the full file to keep the copied summary bounded.

## Acceptance required

Independent CPU contracts cover tile-reference containment, dense lists,
original helper preservation and order-independent integer/tie reduction.
Actual Vulkan prefix fixtures cover partial blocks, >256 references in a tile,
odd dimensions and the 1440 path. Real-bank checks compare final RGB/coverage,
depth bytes, lowest-ID owners and all eight accumulated material channels over
multiple poses, grazing/back views, both supplied phone poses, non-bounded
coverage, no block/query selection, LOD, supersampling, continuity, area lights,
tangent bounds, compact records and stream scheduling. They also verify list
reuse, cancellation, report size, one bank/collider and idle caching. Existing
1.4, compact, witness, refit and queue suites remain independent.

The CPU control cache is already effective. Per-light radiometric basis caching
is a separate follow-up: it needs a source-superposition and invalidation
contract through the full transport before skipping surface shading. It is
not implemented or claimed by this coverage experiment.

Completed native/APK results will be recorded in the acceptance checkpoint.


## Preserved first candidate: pixel gather regression

Runtime `23c4db33151c3d865629454c27c53e6334a1ca35`, run 38934693914,
job 117087748268 passed all 19 workflows, 89 real-bank checks and the 12
Vulkan CSR checks. Depth, owners and integer material reductions are exact in
all nine tested option/pose cases. Its correctness did not imply speed.

On software Vulkan llvmpipe LLVM 20.1.2, reference camera p50 was
433.715517 ms; the first tiled pixel-gather candidate was 977.134485 ms
(+125.29%). Each pixel scanned the full tile list twice; `tile_resolve` alone
was 701.555560 ms. Projecting/counting was only 21.950202 ms, while old
project/raster medians were 78.330924/94.821799 ms. The extra candidate
checks dominated the saved scattered work. No samples were removed.

Tight bounds alone changed moved-light total 313.913454 -> 236.533804 ms
(-24.65%) and visibility 187.233418 -> 114.009917 ms. These are software
measurements, not physical Mali speed predictions. The physical result is
still needed for both hypotheses.

Full first-run data is `checkpoints/LIE_SCREEN_TILES_PIXEL_GATHER_NATIVE.json`.
Only repeated `comparison.passes.rows[].context` objects were replaced by
indices into `comparison.passes.contexts`; expansion was checked equal to the
complete original object. Canonical factored SHA256 is
`9338ce6f0e46380c8f60e77283e5355a7e9ff4e9fd630cdd6399856941b5aef5`.
Original artifact 12061770734, ZIP SHA256
`39f3015a8b833bd92a2cf3230d2e5d77088bd1c07f5c2b9551fb57a76e59bba6`.
The first APK SHA256 was
`7444e25758081c764666561fa1db3bc8c71ac502d40728c8880771b392c6ff8b`.
It is not the final APK. The regression motivated the shared-memory reduction;
that revised implementation requires its own native acceptance.
