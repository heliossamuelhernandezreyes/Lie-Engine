# LIE 2.4: compare surface access architectures

The physical 2.3 report from the Mali-G720 MC7 (2026-10-19 20:01:13 UTC)
measured camera appearance at 63.48 ms for reference1080, 45.59 ms for
surface1080 and 32.11 ms for surface720. Moving a light cost 36.28, 19.59
and 19.99 ms respectively. These are changed-image GPU intervals, not
input-to-photon time or display FPS. The report does not isolate which stage
causes the remaining time. The old source representation and the 2.3 compiled
representation already differ in fine coverage and shadow visibility.

This experiment keeps the same immutable attributed WALL06 bank, material
atlas, assembly, transport and lighting consumer. It compares three executable
representations at BOTH 1080 and 720, with the same 720-square output:

* **Recorrido:** the four-layer per-fragment cell walk used by 2.3, in the
  common 2.4 consumer. It is not a claim to run the original 2.3 binary.
* **Regiones:** the same walk with conservative 8-by-8-cell occupied-depth
  ranges covering every layer, including partial edge tiles. A region is
  skipped only when its ray-depth interval cannot overlap any stored depth.
  Texture cells and captured normal/material/owner values remain unchanged.
  The 256-iteration limit remains; accelerated rays can reach cells beyond a
  formerly exhausted walk. Exact output is checked in the actual test views,
  not asserted universally for every possible view.
* **Envolvente:** a native triangle surface derived from the first depth layer
  of each of the six directional captures. Up-to-32-cell patches refine to smaller
  patches when their measured cell-centre depth error exceeds 3 mm. The shader
  tests original full-resolution coverage and looks up the original material,
  roughness, normal and authored owner; it performs no surface-ray walk and
  writes no gl_FragDepth. The rasterizer supplies interpolated triangle depth.

The envelope adds render geometry. It does not satisfy an interpretation of
LIE in which the ONLY render triangles may be the 97 auxiliary boxes. It is
included as an explicitly selectable architectural alternative authorized for
comparison, not silently substituted for the box-only path. Collision remains
the existing single invisible wall BoxShape3D. Source meshes remain offline;
no original captured source mesh is loaded for rendering.

## Geometry and approximation limits

The initial four-layer adaptive envelope emitted 249,364 triangles per brick
master and 75,620 for mortar: 24,014,564 submitted triangles for this wall.
It was rejected as the proposed lightweight alternative before GPU acceptance.
The front-layer candidate emits 8,228 triangles per shared brick master and
23,664 for mortar: **813,552 submitted triangles** for the wall, versus
1,164 auxiliary triangles for the walking consumers. The geometry packet is
765,408 bytes; it is instanced, not duplicated 96 times in storage.

These counts are not a speed claim. The envelope exchanges fragment search for
vertex/raster work, approximate geometry and cutout coverage. It can lose
overhangs stored in deeper layers and can change silhouettes, seams and
shadowing. The recorded maximum cell-centre axis-depth error (about 2.999 mm)
does NOT bound world-space ray intersections, filtered pixels or image error.
Inter-patch cracks and side-view fidelity require actual image/motion review.
Authored material/owner lookups do not make the approximate geometry exact.

The region packet is 282,624 bytes. All programs and alternative packets stay
resident in the current native consumer for selection; original reference
resources also stay resident for A/B. Resolution/lifetime changes can recreate
resources. Requested bytes are RID accounting, not measured VRAM or process
PSS, and this experiment does not demonstrate a memory reduction.

## Measurements and retained evidence

**Comparar GPU** runs four rotated cycles. Each mode has an initial forced
build, nine warm-up events and nine measured events. There are 216 main
measured events (12 per mode/change group) and 240 retained initial/warm-up
events. The three changes are camera, scalar light power and light position.
Main solves have only outer timestamps; no timed image/buffer readbacks.

A SEPARATE rotated diagnostic repeats all six modes with inner marks for:

* primary surface (only when rebuilt),
* changed-light shadow maps (only when rebuilt),
* node-response preparation (only when rebuilt),
* per-pixel lighting,
* output filter/tone map.

It retains 54 measured and 60 initial/warm-up events, plus its own outer solve
intervals. The report labels its timing separately so instrumentation overhead
can be compared with the main solve. Unbuilt stages have no fabricated zero
sample. Per-event residuals subtract non-overlapping stage durations from that
event's outer duration. Do not sum stage medians, or add stages to whole time.
Residuals include gaps, transfers and other unmarked work; they are not proof
of CPU cost. Shared light transport and static authoring/upload remain outside
the appearance interval and must be considered in a full frame budget.

Full raw rows are saved to `user://lie-surface-access-last.json`. The portable
**Informe** includes main summaries, stage summaries, event counts, actual
backend, geometry counts and source/derived packet identities. Selection and
comparison use the existing validated command transaction; cancellation and
completion restore the selected state. Restoration of the actual rendered
image is checked after all backend/resolution transitions.

## Acceptance

`test_lie_direct_access.py` checks region enclosure and partial edges, packet
layout, depth-discontinuity refinement, explicit masks and the rejected
strict adaptive candidate's owner boundaries. Generated shaders must match
their source and compile. GDScript command checks, CPU rig and persistent
agent checks remain required.

`test_lie_direct_access_gpu.gd` renders the attributed bank in real Vulkan.
It includes the user's latest near-wall pose, the earlier phone poses, front,
side, back and high-elevation views. Region output is compared to the walking
consumer; every representation is compared to the source reference for
silhouette and records actual RGB differences. It checks finite world/owner
values, per-light map invalidation, camera/power reuse, independent-source
superposition, source removal, fresh/cache equality and idle. The actual
six-mode comparison is exercised and every measured outer event is required.

Silhouette IoU is coverage evidence, not image equivalence or photorealism.
Software Vulkan validates execution and reproducibility, never Mali speed.
Physical image/motion acceptance and the new on-phone report are still needed
before choosing an alternative or making a 60/120 FPS claim. Changing Godot is
not part of this experiment; the representational workload is being isolated
first.
