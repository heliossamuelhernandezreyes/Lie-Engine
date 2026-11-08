# Camera hierarchy and refined invisible wall physics, 6.3

The previous 6.2 prototype grouped 781 source-bounds colliders into five wall
envelopes. Its appearance and lighting remained unchanged because no render
work was filtered. The five-box envelope also extended the plinth's thickness
over the entire wall. Axial camera contact occurred about 59.91 mm earlier
than the piece-by-piece reference in the recorded corner probe.

## Physical representation

The new corner proxy retains five wall-body zones with the declared window
opening, two independent plinths, and six independent opening details. The
total is 13 BoxShape3D/StaticBody3D pairs with no drawn proxy mesh. The source
ownership table retains all 781 pieces. Door leaves remain independently
transformed, and grouping is still authored specifically for `corner`.

Separating plinths alone left about 29.78 mm of premature contact because the
sill and frame also protrude. Keeping all these details local makes the axial
probe's conservative camera contact match the per-piece result in both 2102
and 7319 seeds. This is a measured probe result, not an exact union of every
surface. Joint gaps and scan relief remain approximations.

The camera uses expanded OBB slab sweeps, radius 0.025 m and 0.002 m skin.
It projects unconsumed movement onto each contacted plane, for at most four
contacts. Initial overlaps are handled separately: face candidates from
overlapping boxes are tested against the complete union and the nearest clear
candidate is selected. If none is clear, recovery failure is explicit and the
camera remains stationary. The correction is not described as a continuous
collision-free path. Native sphere queries cross-check clear endpoints and
axial contact. Expanded boxes are conservative near rounded sphere corners.

## Visual representation

`lie_construction_hierarchy.gd` builds a hierarchy with a scene root, two wall
groups, spatial segments and a leaf for each complete source job. It uses the
immutable capture page's exact low/high limits and the float32 instance matrix
that reaches the GPU. These bounds include scaled shader tolerances and a
small numerical guard. Physical envelopes never act as visual occluders.

The consumer's square frustum is derived from the actual collision-limited
camera pose, field of view, near/far limits and internal reconstruction size.
An extra pixel guards side planes. A fully outside parent rejects all its
leaves; a fully inside parent accepts them without descending. A crossing
node descends conservatively. This includes near-plane crossings.

The selected leaf mask and the original instance/job packets are validated
and published atomically. Invalid mask size/value leaves the previous pending
transaction intact. Empty selection means the compatibility full-job path;
an explicitly all-zero mask means zero camera jobs.

The renderer creates separate bank-local dispatch lists and parameter buffers
for camera stages 2/3. Each item retains its original global projection offset
and job index, so sample IDs, winner ties, ownership and material inputs stay
unchanged. The full bank jobs and parameter buffers remain bound to shadow
stage 8. Light-field topology and producer receipts remain independent.

Camera masks participate in camera and frame signatures, but not the shadow
signature. A mask change invalidates camera reconstruction. Camera motion can
reuse the full shadow map. View clear/shading/output still run even when no
camera jobs survive, avoiding stale pixels. Resource accounting includes both
sets of small dispatch/parameter buffers.

Diagnostics distinguish the complete logical `samples` and `shadow_samples`
from `camera_samples`, `camera_jobs` and `camera_skipped_samples`. This is
frustum filtering, not proof of occlusion by another wall or a persistent
streaming/residency reduction. No capture pages, LOD or resolution are changed.

## Acceptance and limits

The expanded roof case exposed a pre-existing field adapter error. The 148-node
roof had 62 edges and a transposed row sum of 1.03385367244482. The adapter
re-encoded the transpose with `Model.sparse_factor_bytes`, applying the
original factor encoder's unit-row constraint a second time. Unequal patch
areas permit different row/column sums; the outgoing adjacency therefore
became an empty packet and scene configuration failed, leaving the preceding
scene's image resident. The new helper transposes CSR indices and preserves
every float32 edge weight exactly. This matches the existing offline corner
compiler. Common transport still validates matching gather/outgoing graphs;
no field budget, normal, owner, material or coefficient is loosened.

Headless regression now binds/configures all 148 roof nodes, and the native
suite checks `metrics.configured` for each scene before comparing its images.
This prevents stale prior-scene readbacks from being mistaken for a passing
image comparison. The two failed validation runs are preserved separately.

The headless suite tests source ownership, real physics queries, window/door
openings, contact precision, slide/endpoints, initial-overlap recovery, inner
corners, long movement, parent acceptance/rejection and near-plane retention.
The Vulkan suite pairs full and selected images for complete, close, window,
reverse, overhead, empty, moving-door and roof views, plus a default-resolution
960/1920 close-up. An independent cold shadow pass checks offscreen casters.
The existing reconstruction images are independently compared against 6.2.

Verified run 42499827083 passed all suites and the ten independent reference
comparisons with zero RGBA error and exact depth/alpha. The new native suite
passed 53 checks; the physics/hierarchy suite passed 65. In the default-quality
close view, camera work fell from 1,165,568 to 392,960 samples while full
shadow work remained 1,165,568; color/depth/shadow remained exact. The whole
scene view retained all 781 camera jobs. The selected roof probe is an empty
frustum (0 of 22 jobs), validates successful roof field configuration and
full 528,000 shadow samples; it is not a visible-roof photometric comparison.
Existing HQ construction tests separately cover visible roof reconstruction.

Mobile benchmark comparisons repeat deterministic trajectories with selection
off/on, collect asynchronous GPU timestamps without image readback, restore
controls and copy completed reports. Software Vulkan validates the integration;
physical Android performance remains a separate measurement. If most pieces
are in view, little work can be removed. In-view occlusion, residency streaming,
full house generation and a general character controller are future work.

## Primary references

- https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html
  `cast_motion` ignores initial overlaps; they require a separate query/recovery.
- https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
  Sliding and recovery margins are distinct parts of collision movement.
- https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html
  Frustum filtering removes objects outside the viewport.
- https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
  Occlusion requires an entirely hidden AABB. The custom LIE compositor needs
  its own dispatch filtering; adding physics bodies does not provide that.
