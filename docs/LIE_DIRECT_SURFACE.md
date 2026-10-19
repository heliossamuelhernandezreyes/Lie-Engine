# LIE 2.3: compiled opaque surface path

The previous consumer forwards hundreds of thousands of source disks into
screen-space depth/material reductions, recovers holes, computes base direct
lighting, traverses source TLAS/BLAS for fine visibility and replaces that
base direct term. The alternative removes that dependency chain.

`lie_direct_surface.py` compiles the attributed, unchanged WALL06 bank
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
It creates six orthographic tangent-disk fields, four separated front layers,
explicit empty cells, geometric normals, authored patch IDs and linear
albedo/roughness. One complete captured brick master is shared by 96 affine
instances, with the original layout and tint; another field holds photographic
mortar. These are query fields, not six opaque photographs or a source mesh.

The native path rasterizes 97 auxiliary boxes (1,164 proxy triangles). Within
the entry face, bounded local cell traversal finds a captured surface. Only a
hit writes its actual depth and material into native opaque attachments. The
proxy itself never supplies coverage. Ordinary D32 depth testing selects the
front surface: no float32 attachment blending, manual screen ownership
atomics, source-forward splats or source-shadow BVH queries.

A point light has six 512-square depth views of this same captured field.
Only a moved light's six views rebuild. Camera movement reuses all light
maps; power changes reuse geometry and light maps. Unoccluded node/light
irradiance and indirect-only node irradiance are prepared once per published
transport update. The consumer then composes the indirect field and local
opaque BRDF once. It preserves the shared field's emitter normalization,
source ownership, shape gain and passive transport. It does not add ambient
or a second direct emitter budget.

## Deliberate differences and limits

This is an experimental representation, not exact original disk/uint-sum
parity. The complete shared brick master replaces sparse per-instance sample
subsets. Four depth layers, finite atlas cells, half-float attributes, nearest
cell geometry and a 256-cell traversal bound can change coverage/detail.
Dropped farther insertions and covered layers are reported by the compiler.
These counts describe insertion attempts, not unique lost surfaces.

Light-space visibility replaces the original short 25-mm captured-disk
contact test. Bias, texel resolution, cube seams and PCF change fine shadows.
The common finite-patch visibility gate remains. The alternative does not
certify closed geometry, optical transparency, native Godot shadow participation
or dynamic arbitrary scene objects. Runtime collision remains the existing
single invisible BoxShape3D; auxiliary render proxies are not colliders.

The tested contract is the static authored wall, camera/light motion,
exposure, source enable/disable and opaque material response. Historical
per-source optimization/recovery controls describe the reference path.
Default native geometry uses the compiled full-master field regardless of
historical sample-LOD/selection switches. No interpretation as exact parity
for those switches is permitted.

Both executable consumers remain in the A/B application. Reference allocations
stay resident; native requested bytes are additional and separately reported.
This package does not demonstrate a memory reduction. Published transport
RIDs are borrowed only during the owning effect/transport lifetime. The native
consumer owns and releases its atlas, attachments, pipelines and sets.

## Verification and physical acceptance

Stage with Godot 4.7.2 and `tools/lie_direct_build.py` after the pinned native
module build. It restores and verifies the real source bank, compiles the
fields and includes their exact sizes/SHA256 and original attribution.
Python tests exercise actual tangent-disk coverage, layers/truncation,
provenance, linear color, roughness and back-facing rejection. GDScript
commands use the existing validated `command()` transaction path.

`test_lie_direct_gpu.gd` runs actual Vulkan against that bank, compares real
reference/native images at identical resolution from front/side/back and near
views, checks authored node IDs and source superposition, disables/re-enables
sources, compares cached and fresh geometry/shadow maps, verifies per-light
invalidation and cached idle. It also exercises the actual paired benchmark
and portable report. PNGs and unfiltered timing/event histories are retained.

The first real Vulkan experiment FAILED coverage: IoU 0.80 frontal and 0.51
oblique. Adding sub-ULP increments to a multi-metre eye distance could stall
cell traversal. Rebase at box entry and use metric cell progress; do not
remove this correction or reduce validation to a mocked image. The corrected
four initial views reached IoU 0.9681–0.9861. This is silhouette agreement,
not proof of equivalent materials or realistic animation.

The benchmark alternates reference1080, surface1080 and separately labelled
surface720, all with 720-square output. All initial block/cold-map and warmup
events remain in the report. Whole appearance includes primary rendering,
changed light maps, node preparation, shading, inter-stage gaps and output.
Static field authoring/upload and shared light transport are separately scoped.
Software Vulkan establishes execution/correctness, never Mali speed.

On the physical Mali-G720 MC7, compare image and continuous camera/light
motion, then use **Comparar** and **Informe**. Camera and moved-light p95
need to approach the total changed-frame budget (16.67 ms for 60 updates/s),
with transport and presentation considered. Display FPS can include cached
images. A measured speedup, acceptable fine shadows and stable coverage are
required before selecting this architecture for production or removing the
reference renderer. Godot can submit this native path; changing engines is
not a prerequisite for testing the architectural hypothesis.
