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

## Acceptance

Before APK delivery, require the Python membership/generator regressions,
changed GDScript commands, CPU rig/agent regressions, independent exhaustive
float64 versus actual Vulkan page/BVH queries, and full native images/depth,
cache, shared lease, moved light, area, resize and comparison checks. The native
workflow preserves its logs and JSON evidence. Software Vulkan measurements
do not establish speed on the physical Mali-G720 MC7; a paired phone report
is still necessary.

Local environment recovery: on 2026-10-16 the existing Godot executable exited
139 even for `--version`. Its bytes differed from the retained official ZIP.
Restoring that binary recovered `4.7.2.stable.official.ed1daf0bf`; the 12 page
command checks then passed. This failure was not an application measurement.
