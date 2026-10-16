# LIE 1.8: hardware evidence and compact shadow records

This iteration isolates one data-layout change and adds native observability.
It does not establish physical Mali performance. The original 80-byte source
bank and accepted 1.4 route remain available, with compact shadows OFF at start.
The 1.7 tangent-bound setting is held constant within each 1.8 comparison.

## Compact shadow view

`tools/lie_shadow_view.py` copies bytes 0–31 of each original 80-byte source
record, preserving position/radius, normal/gray, every float bit and source ID.
There is no quantization, source reorder, proxy occluder or altered intersection.
Only the visibility, witness preparation and exact trace shaders consume it.
Projection, rasterization and material reconstruction retain the original bank.
The shader generator preserves the original traversal functions verbatim.

For the supplied bank (521257 records, SHA256
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`),
the extra immutable view occupies **16680224 bytes**. Its SHA256 is
`363a7718495f669144454f9819e254d0afa7530bfedc39a9d1d6d8a31d5f0733`.
A device-scoped lease shares this extra upload. Both views remain resident;
this is not a total-memory reduction. Cache lines and compiler loads determine
the actual traffic reduction; a 60% record-size reduction is not a 60% speed claim.

## Native diagnostics

The MIT GDExtension uses pinned Arm libGPUCounters
`378c7b59e2dae87cbbffb0ac9cf96ed13c939823` and godot-cpp 4.5
`e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` in actual Godot 4.7.2.
Build profiles include RefCounted and OS (required by the binding library's
printing implementation). Android builds use NDK r28c, static C++ runtime and
16 KiB ELF load alignment. Dependency licenses and build identities are bundled.

The extension checks the Mali device node, configures counters supported by the
actual product and returns explicit errors when driver access is unavailable.
It does not request root or change permissions. A missing extension is reported
separately from a denied or unsupported device. A failed start or sample is not
reported as zero utilization. Counter uint64 values are decimal strings to
preserve precision in JSON; floating derived values retain their units.

Selected counters cover active cycles, ALU/load-store utilization, atomics,
external/L2 traffic, bus stalls, divergent instructions, all-register warps and
compute/graphics/CSF activity where the product supports them. These are
**whole-device interval measurements**, including other apps and presentation,
not isolated per-dispatch counters. The initial interval is discarded. Hardware
timestamps are not calibrated to Godot's timestamp clock.

Frequency and GPU temperature are best-effort reads from explicitly GPU/Mali
Linux devfreq and thermal nodes, with standard ABI units and exact sensor paths.
Unreadable sensors have an availability reason and no invented value. Android's
API-30 thermal status is resolved dynamically; it describes device thermal policy,
not GPU temperature. No thermal or clock control is claimed.

## Measurement contract

“Comparar GPU” alternates original/compact order for three rounds. It retains
54 measured events (nine per mode/event kind) and 60 predefined warm-up events.
There are no hardware sampling intervals or GPU readbacks in those timed events.
The native sampler is released before the paired run. Passive telemetry at block
boundaries is outside event timing. All samples and spikes are retained.

After clean timing, six separately instrumented work events read 32 counter bytes
each. Original/compact must have identical receiver, cache, witness, node and disk
test counts. Only then is native sampling probed. If available, separate warmed
camera/power/light-position batches in each mode collect six hardware intervals.
If unavailable, the reason and sensor availability remain in the report.
Cancellation stops sampling and restores the original scene/options.

Host event times describe command application, render callback wait and the
existing six-frame drain. They are **not GPU completion, queue residence or
input-to-photon latency**. Display FPS can include idle cached images. Requested
RID bytes are not measured VRAM/PSS. Full raw evidence is saved as
`user://lie-gpu-diagnostics-last.json`; the copied summary retains both mode
timings, scene, work counters, hardware results and telemetry availability.

## Validation and interpretation

Completed results, exact runtime/APK identities and preserved failures are in
[the acceptance record](checkpoints/LIE_GPU_DIAGNOSTICS_ACCEPTANCE.md).

Python checks verify exact bytes and generated shader equations. Actual Vulkan
acceptance uses the attributed real bank, compares images/depth for camera,
light displacement, area, LOD, continuity, resize, queue and box options, checks
shared lifetime and identical work counts, and tests the compact shader against
the independent float64 exhaustive oracle. Existing 1.4/queue/witness tests run
separately. Software Vulkan is correctness evidence, not Mali speed evidence.
The APK verifier checks the full bank/view byte relation, ARM64 ELF, 16 KiB load
alignment, native library presence and licenses. Native sampling success still
requires a compatible physical driver.

Local first-build failures were binding-profile OS omission and a stale CMake
configuration; the revised profile built and loaded successfully in a fresh build
directory. No failed physical or GPU timing has been discarded.

The first full-repository regression run exposed an integration failure: tracking
an active GDExtension descriptor made unrelated source-only laboratories try to
load an unbuilt binary. The descriptor now lives as a template outside the Godot
project and is installed only after a successful native build. A plain checkout
therefore does not activate the optional module; staging 1.8 requires its real
build. The failed run is retained in GitHub Actions, not reclassified as a pass.

Further architecture experiments depend on the evidence: native rasterization
for compute splat atomics, finer shader/register partitioning, and cached
per-light radiometric bases remain separate proposals, not implemented claims.

## Primary references

- [Arm libGPUCounters](https://github.com/ARM-software/libGPUCounters)
- [G720 counter definitions](https://arm-software.github.io/libGPUCounters/immortalis-g720_and_mali-g720_counter_reference.html)
- [Arm Vulkan barriers](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/vulkan-synchronization-how-pipeline-barriers-map-to-mali-gpu-hardware)
- [Android thermal API](https://developer.android.com/ndk/reference/group/thermal)
- [Android NDK releases](https://github.com/android/ndk/releases)
