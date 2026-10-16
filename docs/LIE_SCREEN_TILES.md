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
6. Assign one invocation to each pixel, within its tile. Determine minimum
   positive depth, choose the original minimum source ID on a depth tie, then
   accumulate the original uint material terms. Write depth/owner/material once.

The pixel loop still atomically marks every original equal-depth source flag,
and list construction still uses atomics. This is not an atomics-free renderer.
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

This exchanges contested scattered writes for conservative list construction
and extra candidate checks/reads. More work inside a tile can offset any saving
from fewer global material atomics. Hardware behavior must be measured; no
Mali speedup follows from software-Vulkan correctness or timing.

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
