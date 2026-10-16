# LIE 1.5: addressed source pages

LIE 1.5 keeps the accepted 1.4 dedicated kernels and adds a separate world
visibility kernel. A local source coordinate directly addresses a grid cell;
that cell contains a CSR range of original captured sample IDs. Every candidate
still uses the original tangent-disk intersection. Instance transforms share
the same immutable local index. Camera projection and rasterization are unchanged.

This removes BLAS node traversal for accepted page queries, not all searching:
scene instance selection, ray traversal through cells and exact candidate tests
remain. Dense cells (over 256 references), unavailable roots and unresolved
traversal fall back to the original full BLAS. Existing persistent visibility
and exact blocking witnesses remain in use. No clear-space certificates,
shadow interpolation or changed capture geometry are introduced.

The compiler binds the index to the immutable bank and source BLAS SHA-256.
The runtime validates packet ranges and leases one immutable GPU buffer per
device/hash. The current wall packet is 4,231,312 bytes; this is requested buffer
storage, not measured process memory or VRAM. Page counters are cumulative and
enabled only by the existing explicit visibility diagnostics control. Ordinary
phone rendering and the timing comparison do not read back GPU images/buffers.

## Paired comparison

`Comparar GPU` compares the original 1.4 split visibility binary with the new
page binary. It alternates OFF/ON order over three rounds. Each block resets
private witness hints and visibility, runs initial geometry plus nine camera,
power and light-position warm-up events, and then measures the same nine
events. There are 54 measured events and 60 separately retained warm-up events.
Each mode/kind has nine measured samples. No observation is removed after
seeing its timing. The starting scene and restoration status are retained.

`Informe` / `Copiar` includes both modes, CPU command timing, per-stage GPU
timing, warm-up summaries and the exact paired scene. Full events and raw
timestamps are saved as `user://lie-spatial-pages-last.json`. The original
visibility route remains available with the page checkbox off.

## Validated runtime and acceptance

Runtime commit `e0f26bd45dea736c51eb005c2bc9316159269db7`, tree
`fa887bd04232712a07a45cfedf5387dbfe268887`. All 19 triggered workflows passed.
Dedicated native/export run 38828005634, job 116739905911, artifact 12016008653.
Three page Python tests, three prior kernel tests, 12 page command checks,
two changed shader SPIR-V checks, CPU rig 247 and CPU agent 25 passed locally.
The actual Vulkan oracle passed 588 checks over 282 queries in 11 fixtures;
page results were identical to the original BLAS, with maximum error against
independent exhaustive float64 of 1.173e-6. Dense-page fallback was exercised.

The real-bank Mobile test passed 58 checks, plus all inherited regressions.
Initial output matched the actual 1.4 scene exactly; four tested camera views
retained exact depth and coverage IoU 1.0, with RGB maximum difference below
7.71e-7. Four moved-light comparisons against uncached BLAS had zero RGB
difference. Area lights, LOD/continuity, resize, independent page leases,
cached idle, one bank upload, one invisible collider and stable requested
allocation also passed. The paired diagnostic retained all 54 measured and
60 warm-up events, 1,050 timestamp rows, nine GPU/CPU samples per mode/kind,
the exact scene and exact state restoration. Its portable report fit below
16 KiB.

## Performance result: no demonstrated acceleration

These are nine-event-per-group totals at 1080 on **software Vulkan (llvmpipe)**,
not the Mali. The paired scene itself is retained in the native JSON; its
camera matches the close oblique phone view, but its light/power/preset differ
from the earlier phone report. Do not compare those separate reports causally.

| Change | Original 1.4 p50 | Pages p50 | Original p95 | Pages p95 |
| --- | ---: | ---: | ---: | ---: |
| Camera | 403.683 ms | 405.198 ms | 413.757 ms | 419.213 ms |
| Light power | 115.614 ms | 115.336 ms | 120.546 ms | 124.930 ms |
| Light position | 167.388 ms | 170.718 ms | 183.608 ms | 183.050 ms |

The light-position GPU median is **1.99% higher** with pages. Its visibility
stage median rises from 53.004 to 59.234 ms (11.75%). Camera visibility rises
from 8.151 to 11.472 ms. This negative result is retained, including every
measured event and all warm-up work. No outliers were removed. Direct cell
addressing alone has not established faster visibility. The run does not
identify a specific register-pressure, memory-bandwidth or compiler cause.
The original binary remains selectable; a paired physical-phone report is
necessary before claiming a Mali improvement.

The immutable packet is shared as one 4,231,312-byte GPU allocation; six
descriptor rebuilds covered resizing and borrowed lease changes. Total requested
appearance buffer/image bytes are 284,812,312. Native explicit diagnostics
observed 5,528,813 traversed cells, 251,763,186 exact disk tests and 301,309
fallbacks cumulatively across the test, not per frame or per benchmark event.
The final counter snapshot has instrumentation disabled and retains earlier
diagnostic work. These counts are not ordinary phone-frame measurements.

## APK and durable evidence

`LIE-Paginas-1.5.0.apk`, package `org.lieengine.wallruntime.v150`, code 15,
60,263,351 bytes, SHA-256
`5413ea091e79de500dceafb25f9ecd461cf8a8e69d1f2948273dc39d4bad7d9e`.
The official Godot 4.7.2 Android template was normalized, aligned, signed and
verified by the workflow. The downloaded artifact ZIP digest is
`a0739b05c7f64ae49b3d59874e5c602595dfa77402013759a317e675722efc96`.
APK bank and spatial packet bytes were verified against their SHA-256 identities.
No physical Android device has been tested in this environment.

Full native observations, oracle cases, local checks and artifact identities
are preserved in `docs/checkpoints/LIE_SPATIAL_PAGE_*.json`. Capture banks and
the APK remain outside Git. The native workflow also preserves its logs and
JSON evidence. Install, choose the desired scene, run `Comparar GPU`, then
`Informe` / `Copiar informe` to collect paired phone evidence.

Local environment recovery: on 2026-10-16 the existing Godot executable exited
139 even for `--version`. Its bytes differed from the retained official ZIP.
Restoring that binary recovered `4.7.2.stable.official.ed1daf0bf`; the 12 page
command checks then passed. This failure was not an application measurement.
