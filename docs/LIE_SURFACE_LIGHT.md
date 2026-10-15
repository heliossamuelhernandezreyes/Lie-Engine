# Captured relief and bounded contact shadows — WALL09 / 0.6

This experiment refines **direct** appearance using captured world positions
and geometric normals. It leaves the accepted source-separated field and its
passive bounce budgets intact. It adds no source mesh draws, capture edits,
normal maps, collision proxies or full-frame position atlas.

## Shared implementation

`lie_surface_light_transport.gd` extends the common field. Its stage 6 exports
one stable GPU storage buffer: 16-byte `[surface_count, light_count, 16, 1]`
header, sixteen vec4 light descriptors, then eight surface-count vec4 direct
irradiance channels. Descriptor pairs contain world position/radius and
power divided by the existing emitter cap/distance-squared floor. Direct
irradiance uses the exact field weights, visibility, transmittance and area.
It is published after direct normalization, before bounce accumulation. No
runtime CPU readback supplies appearance. The field owns this RID; consumers
borrow it, and shut down before the producer as in previous laboratories.

`lie_surface_direct.glslinc` provides the common point-source response and
visibility-gated replacement. The wall adapter builds the same convex source
stencil used by the accepted appearance/recovery path. For each light:

* Subtract its exact old direct radiance from the baseline sum.
* Preserve all remaining indirect radiance.
* In detail mode, replace direct radiance by the local captured position and
  normal response, gated by the original finite-patch visibility/transmission.
* In contact-only mode, attenuate the existing direct radiance; never brighten.

This is a local direct-light quadrature refinement. The image-space integral
is **not** certified as a finite-area flux integral. It is not view-dependent
GGX, native Godot lighting, measured photometry or refraction.

`lie_contact_surface.glslinc` traverses at most 2.5 cm toward each light, with
0.3 mm normal bias and 4–32 deterministic samples (default 12). A candidate is
an actual observed source tangent plane bounded by its pixel cell. Its exact
ray intersection must lie inside that cell and the metric traversal interval.
Missing/recovered/off-screen pixels do not cast these additional shadows.
There is a smooth fade in the last quarter of the traversal range.

Consequently, hidden/off-screen occluders and sub-step features may be missed.
The existing finite-patch visibility handles the larger scene scale. These
are screen-space contact shadows, not a world-space visibility solution.

## Cache and allocations

The new appearance stage runs after the original reconstruction/recovery and
before tone mapping/downsampling. Both switches OFF take the accepted path.
Lighting and contact options invalidate shading only. Exposure reruns output
only; an idle image remains cached. Resizing preserves the bank/transport RID.

Recovered pixels retain an extra 32 bytes of source-supported world/normal
data per record: 2,097,152 bytes at the existing 65,536-record capacity. They
can receive contact shadows but never act as contact occluders. Overflow
keeps the old appearance. The transport bridge reserves 272 + 128*N bytes
(111,888 bytes for 872 nodes). Requested buffer sizes are not Android PSS.

`lie_gpu_pass_profile.gd` asynchronously collects RenderingDevice timestamp
deltas. The app/agent exposes per-pass GPU p50/p95 and sample counts. These
describe changed-image solves; idle cached frames do not produce solve
measurements. They are not CPU time, GPU utilization or sustained phone FPS.

## Validation and research

The independent float64 oracle enumerates all bounded observed pixel-plane
intersections; it does not mirror the GPU ray march. Fixtures cover flat and
sloped surfaces, a step, real missing support, reverse light, rigid rotation,
translation and the metric range limit. Real Vulkan fixtures execute the same
common GLSL includes and the direct bridge against the accepted 15-scene field
oracle. Full-wall tests compare OFF to WALL08, contact-only monotonicity,
coverage, cold/cache equivalence, resize, exposure, idle and source residency.

Local checks: five new Python tests, six common-field tests, Godot import,
nine validated UI/agent commands, 247 rig and 25 agent-session checks pass.
Actual Vulkan/Android results are recorded in the continuation checkpoint.

Primary research: [Epic contact shadows](https://dev.epicgames.com/documentation/unreal-engine/contact-shadows-in-unreal-engine)
and [Unity HDRP contact shadows](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition%4014.0/manual/Override-Contact-Shadows.html)
use bounded depth-buffer rays for close detail. This supports the scope and
limitations; it is not evidence of this implementation's quality or speed.
Godot 4.7.2 CompositorEffect/RenderingDevice suffice for this stage. No core
fork is needed until native depth/shadow participation or public light-buffer
access establishes a concrete missing engine capability.

## Preserved local failures

* The first float64 rotated fixture landed exactly on a pixel corner; strict
  half-open cell comparisons exposed numerical corner ties. Queries now use
  a declared sub-pixel offset. This is not proof of all real-camera corner ties.
* First staging rejected a truncated local historical WALL04 bank (44,040,192
  bytes, SHA256 25ddcaf3f14ebe193f2dfba505db9d4cf99a858b9f2d42d87f0a456ca08e8a25).
  The original verified 61,767,760-byte source was restored from the previous
  accepted stage and its required f6f7d9f7… hash rechecked. No source recipe or
  accepted bank hash changed. The failed stage was left intact.
