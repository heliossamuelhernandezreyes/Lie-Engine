# Seeded masonry with actual source-face variation

The house generator now uses the same complete scanned brick with four rigid
orientations, modest authored material variation and half-lap running bond.
This follows `LIE_SCANNED_MASONRY.md`; the attributed original source and its
38 calibrated captures remain unchanged.

## Geometry and variation

Whole bricks keep scale (1,1,1). The finite orientation group is identity,
Y180, X180 and Z180, all proper rotations with determinant +1. This changes
which original scanned surfaces are visible without reflecting or deforming
the object. A 90-degree roll would change course height/thickness; it is not
silently inserted into these fixed courses. Small additional rigid rotations
are bounded by 0.35° / 0.40° / 0.225° on local X/Y/Z. Position jitter is at
most 0.3 mm per local axis. Conservative box tests retain over 4 mm clearance
between neighboring pieces in the tested seeded houses.

Brightness gain is in [0.88,1.12], warmth parameter in [-0.05,0.05], and
roughness offset in [-0.045,0.045]. These are **authored instance modifiers**,
not additional photographed materials or measured weathering. Original source
RGB and roughness bytes remain intact. The existing GPU instance tint and
roughness fields consume these modifiers directly. No new texture per brick,
no per-frame randomization and no copy of the source bank per placement.

Random fields use a versioned seed/section/row/half-cell/channel key and an
integer avalanche mix. Canonical recipe values are quantized to nine decimal
places. Source positions, orientations and material decisions restore exactly
when returning to a seed. Generator API accepts any uint32; the native lab
ships precompiled seeds 2102 and 7319.

## Intercalated courses and genuine half bricks

Even courses start with whole pieces. Odd courses start and end with half
pieces; interior joints shift by half a module. Doors/windows subtract the
same half-module intervals from brick placement and mortar. A piece crossing
an opening edge becomes a properly oriented half, rather than being stretched
or drawn across the opening.

`lie_masonry_half_blender.py` derives two closed pieces from the original
canonical mesh. Exact coincident vertices are reconnected only after checking
that their original colors are identical. The source has 357,956 glTF vertices
and 249,996 unique canonical positions; welding this duplicate representation
does not move the surface or change its color. The cut planes are X=-4 mm and
X=+4 mm; the derived width is (whole length - 8 mm joint)/2. All retained
source surfaces remain at their original coordinates before an explicit
pivot translation for capture.

The exposed planar cut is closed and declared as an **authored clay face**,
RGB linear (0.30,0.18,0.125), roughness 0.85. It is not part of the original
scan. Closed-edge topology, planar cap positions and outward cap normals are
checked independently. Both derivatives pass the same common capture compiler,
semantic frame, material preflight, asset identity and shared bank contracts.

The camera and shadow splat stages also enforce the exact cut plane in local
source space. Large LOD supports cannot extend a retained source face past the
saw cut. Instance metadata carries the clip side/plane; legacy whole-brick
instances have zero clip side and retain their previous behavior.

## Reconstruction and native comparison

The source-bank prefix is byte-for-byte unchanged. Added data consists of two
50,688-sample cut masters and an additional 1,024-sample whole-brick LOD.
The final shared bank is **55,070,720 bytes**, five masters, with SHA recorded
in the checkpoint. Mortar remains separate authored boxes, grouped into short
spans and split at openings. Roof and floor are unchanged simple authored
assets.

| Seed 2102 | Whole bricks | Half bricks | Total instances | Native invocations |
| --- | ---: | ---: | ---: | ---: |
| Wall | 124 | 16 | 208 | 599,424 |
| House | 2,336 | 208 | 3,784 | 2,999,552 |

The house still represents 2,440 whole-brick equivalents. It uses 2,544 actual
pieces because boundary pieces are now cut. Course orientation histogram is
648 identity / 641 Y180 / 606 X180 / 649 Z180 for this seed.

The lab exposes the existing validated `command()` interface for `style`:
`legacy`, `uniform` and `varied`. `uniform` keeps running bond while disabling
material and pose variation. `legacy` regenerates the previous stack-bond
template. The isolated brick also exposes `face` 0..3, backed by compiled
recipes. Rejected commands remain atomic. Example:

```json
{"op":"set_values","values":{"mode":"house","style":"varied","seed":2102}}
```

The before/after house images use the same camera, light, seed and renderer.
Both are rendered anew with the current bank/LOD policy; the left image is a
compatibility recipe, not a reused screenshot from a different lighting setup.

## Validation and remaining limits

Local Godot 4.7.2 / Mesa 25 / llvmpipe LLVM 19 passed **74 actual native
checks**. They cover the prior capture/material/depth/cache controls, three
construction styles, four original source orientations, tint reaching GPU
instance packets, rendered seed/style restoration, source sharing and release.
Python ran **268 tests: 267 passed, one skipped**; rig 247 and agent 25 checks
also passed. `lie_masonry_bond_verify.py` checks the preserved bank prefix and
both closed saw-cut sources. Independent CI additionally runs the original
bank against the modified consumer before testing the new construction bank.
CI run 42338266767 independently completed every job step successfully:
42 native compatibility checks and 74 improved-construction checks, with
268 Python tests (267 passed, one skipped), on llvmpipe LLVM 21.1.8. Its
55,070,720-byte bank has the exact same SHA as the local bank. Artifact
ID/hash and the observed step results are recorded in the checkpoint.

These changes improve assembly and repetition, not structural certification.
Corners remain prototype butt joints; lintels, foundations, roof framing,
weathering correlated with exposure and additional genuinely scanned masters
are future work. A single scan still repeats its characteristic damage.

The higher-density house LOD uses about 480.7 MB exclusive buffers/textures
plus 55.1 MB shared samples in the 720-output desktop validation configuration.
Fewer instances do not prove lower GPU memory or faster rendering. The native
lighting remains point-light GGX plus authored ambient; shared indirect-field
integration, low-end/mobile LOD scheduling and physical Android measurements
are pending. No new APK is claimed.

## Reproduce and attribute

Use the previous capture pipeline to obtain the complete source and original
masonry bank. Then:

```bash
blender -b -t 4 --python tools/lie_masonry_half_blender.py -- --canonical /tmp/scan/source-canonical.npz --output /tmp/halves
PYTHONPATH=tools python tools/lie_masonry_bond.py --base /tmp/masonry --half-sources /tmp/halves --output /tmp/bond
PYTHONPATH=tools python tools/lie_masonry_bond_verify.py --base /tmp/masonry --bank /tmp/bond --half-sources /tmp/halves
PYTHONPATH=tools python tools/lie_scanned_masonry_shader.py
PYTHONPATH=tools python tools/lie_scanned_masonry_stage.py --bank /tmp/bond --stage /tmp/bond-stage
```

Open the isolated project with Godot 4.7.2 Mobile/Vulkan. Source credit:
**Stratford New Place Brick Ver 2, Centre-of-Archaeology, CC BY 4.0**.
https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a
https://creativecommons.org/licenses/by/4.0/
Keep attribution and derivative-cut/material declarations with redistribution.

The initial cut attempt could not close split glTF boundaries. A tolerance-based
weld still left source seams open and was rejected. The accepted exact-position
reconnection preserves identical colors, and both final cuts pass closed-edge
verification. The failed logs remain alongside the data evidence.
