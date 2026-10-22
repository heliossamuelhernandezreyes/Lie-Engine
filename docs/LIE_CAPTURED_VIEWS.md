# LIE 2.5: compile visibility, bound runtime reconstruction

The physical LIE 2.4 report identifies primary visibility as the dominant
camera cost. At 720, regions spends about 26 ms in the primary diagnostic;
the envelope still spends about 23.9 ms and its light maps regress to about
61.3 ms. The main and stage samples are separate. The preserved phone summary
is `checkpoints/LIE24_MALI_SURFACE_ACCESS.json`.

This experiment changes the primary representation rather than adding another
acceleration structure to the cell walk. It is an approximate relightable
impostor. The first physical phone report reduces camera appearance intervals,
but also exposes near-camera visibility failures; see the diagnosis linked below.

## What moves out of the frame

`lie_direct_views.py` projects the accepted four-layer, six-direction captured
cell fields into 64 orthographic reference directions per master. A deterministic
nearest-depth reduction stores one visible depth and one integer provenance
code per texel. Every code identifies the original atlas cell, face and layer.
The compiler renders finite occupied cell squares; it neither fills holes nor
loads an original source mesh. This preparation is offline, not repeated by a
camera update or hidden inside a timed event.

The octahedral grid is 8 by 8. Capture rectangles have a longest dimension of
192 for the shared brick and 512 for photographic mortar; their aspect ratios
follow the authored bounds and capture basis. They are packed into two integer
RG32 texture atlases. The original full-resolution material/normal fields stay
resident. The compiler records source and derived packet sizes/hashes.

## Runtime contract

The unchanged invisible boxes supply conservative raster coverage and physics
remains the existing single wall collider. Each proxy vertex computes three
angular reference indices arithmetically. For each entry fragment the new
consumer performs, at most:

* three candidate reference views;
* three view-depth projections per candidate;
* two original-field depth refinements per candidate;
* original normal/material lookup for accepted candidates.

This is a maximum of nine reference-depth, six original-depth and six attribute
texel reads per proxy fragment. There is no DDA, binary search, runtime source
sample projection or fallback to the walking shader in this primary program.
Early rejection can reduce these counts. Total work still depends on projected
box overlap and the number of visible instances; this is not constant total
scene cost. Shader depth writes and cutout coverage also remain.

A second **Vistas simples** program is a deliberate minimum-work control. It
selects one angular reference and fetches exactly one captured depth plus the
original normal/material texels. It does no reprojection correction or original
source-depth refinement. Its geometry can therefore shift, jump, leave holes
or occlude the wrong object under camera changes. It is not image-equivalent
and has no near-camera accuracy acceptance claim; quality differences are
retained alongside timings. It uses the same lighting and regions shadows.

In **Vistas ajustadas**, the nearest valid candidate supplies depth and material. Views are NOT blended
across incompatible owners, and three candidates do not constitute a guarantee
of continuous or exact view interpolation. Fixed reprojection can select a
wrong or missing surface near discontinuities, thin features and grazing views.
Full-resolution material lookup does not recover visibility lost in a capture. The simple control samples the original material cell identified by the coarse capture and can also lose fine texture sampling fidelity.

Shadows independently use the same `regions` backend in both compared modes.
That path still performs cell queries, and a moved light still builds six
512-square faces. The new camera program does not imply constant-cost exact
dynamic shadows. Shared per-source transport, node preparation, BRDF and output
mapping remain common to isolate the visibility change.

## Comparison and acceptance

`lie_direct_views_lab.tscn` exposes **Vistas capturadas**, **Regiones (2.4)**
**Vistas simples** and the source-disk reference using the existing transactional command API.
`Comparar GPU` pairs regions/adjusted views/simple views at both 1080 and 720 with the same 720 output.
Four rotated rounds retain 216 main measured events and all initial/warm-up
events. A separate inner-mark diagnostic retains 54 measured events. Each
main mode/change group has 12 observations; each stage group has three.
No timing readbacks or silent backend substitution are allowed.

The report is `user://lie-captured-views-last.json`. Main whole intervals and
stage medians remain separate. Atlas compilation/upload and shared transport
are outside the appearance interval, as in the accepted comparison; their
costs must be included separately in loading/memory/full-frame assessment.
Requested resource bytes are not measured VRAM/PSS. All A/B representations
and old source resources remain resident in this laboratory.

Tests cover the angular address, integer provenance, independently expected
near/far visibility and real empty space. Actual attributed-bank Vulkan checks
compare seven fixed cameras and two moving-camera sequences (the simple control records its approximation without passing the adjusted mode's coverage gate), preserve PNGs and
RGB/coverage differences, test original owner ranges, source superposition,
source removal, cache/fresh equality, per-light invalidation, idle and actual
post-benchmark image restoration through resolution changes.

Coverage IoU is not a photorealism or temporal-stability certificate. The
motion-frame differences are image differences, not motion-compensated error.
Real phone motion review and physical GPU measurements remain necessary.
The 2.5 wall adapter is not yet a general animated-character implementation.

## Preserved negative results

The initial floating-point extent-to-resolution conversion occasionally emitted
193 rather than the requested 192 texels. The independent bounds contract
caught it; integer dimensions now clamp to their declared maximum without
shrinking the physical bounds. The first native captures show visible changes
in mortar joints and relief relative to regions; these are retained and not
described as exact image equivalence.

Design references:

* [Epic: Impostor Baker](https://dev.epicgames.com/documentation/en-us/unreal-engine/impostor-baker-plugin-in-unreal-engine).
  Few-view sprites and explicit parallax/quality tradeoffs; mainly distant LOD.
* [Wu et al., RiLoD (2025)](https://doi.org/10.1111/cgf.70183).
  Relightable captured geometry/material representations for distant objects.

This experiment is not a reproduction of either implementation and does not
inherit their speed or quality results. Godot replacement is not needed to
test whether moving visibility into the asset removes the measured workload.

## Recorded execution gate

Runtime commit `2836e6b941ae638f4788fe6c28755e7b8bfdc581` passed 148 local
attributed-bank Vulkan execution/comparison checks and an additional nine
actual resource-replacement checks. The common light field passed 374 checks
in 15 scenarios. CPU rig (247), agent session (25), probe (12), both original
and new command transactions (20 each), and 22 relevant Python contracts pass.
The additional lifetime script is `test_lie_direct_views_lifetime.gd`; it runs
against the same staged runtime without changing its production modules.

In the seven local fixed views, adjusted/source silhouette IoU ranges from
0.9600 to 0.9842. The simple control falls to 0.8675 in a near-wall view and is
not accepted for visual quality. These numbers do not certify texture fidelity
or temporal stability. All 216 main and 54 stage events were retained.

Local evidence and its limits are retained in
`checkpoints/LIE_CAPTURED_VIEWS_CHECKPOINT.json` and the complete compressed
`checkpoints/LIE_CAPTURED_VIEWS_NATIVE.json.gz`. Software timings remain marked
as software results. Signed Android delivery and CI identities are recorded
in the checkpoint after successful verification.

## First physical report and a new failing camera

The 2026-10-21 phone report now demonstrates lower camera appearance cost on
Mali, alongside severe simple-view deformation and adjusted-view coverage
failure at the newly reported pose. See [the reproduced diagnosis](LIE25_PHONE_POSE_DIAGNOSIS.md).
This supersedes the earlier absence of physical measurements; it does not
establish acceptable near-camera image quality or continuous motion.

The recovered native-cell and reverse-Z experiment is documented in
[LIE_NATIVE_DEPTH_RECOVERY.md](LIE_NATIVE_DEPTH_RECOVERY.md). It substantially
reduces the reproduced coverage failure, while preserving unresolved precision,
grain and very high auxiliary triangle cost. It is not a mobile replacement.
