# Complete scanned brick, calibrated views and seeded masonry

Implemented on `work/lie-scanned-masonry`, based on the independent matte
brick experiment. The user requested a genuine volumetric source instead of
the simple reference fixture, with captures and seeded walls/houses.

## Source and what was actually captured

**Stratford New Place Brick Ver 2**, Centre-of-Archaeology, CC BY 4.0.
Original: https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a
Public dataset route: Objaverse 1.0, object
`6077f6801089403993f6a6612ff5739a`, `glbs/000-013`.
Source SHA-256:
`b55b9d584fcfa6d7baf9e1d815c02578d91e092efc4cf88a47c23bbee643031b`.
20,324,708 original bytes, 500,000 triangles, 357,956 glTF vertices.

This object supplies **linear vertex COLOR_0**, not an 8K photographic atlas.
Its material declares roughness 0.6 and metallic 0. Acquisition lighting in
the original color has not been removed or certified absent. Geometric detail
is actual source topology; no generated pores or invented material maps.

The authored semantic frame starts with source +Y front, +Z up, -X right,
followed by a documented proper rigid fit of an explicitly selected broad
surface. No reflection, aspect-ratio semantic inference or flattened geometry.
Scale uses the publisher's nominal eight-inch length on source X; it is not
independent metrology. Final whole-object bounds are approximately
0.199520 × 0.057407 × 0.100616 m after alignment.

`lie_scanned_brick_prepare.py` uses the common asset compiler and preflight.
The five immutable LODs contain 480,000 / 64,000 / 4,096 / 512 / 128 samples,
548,736 total, 80 bytes each. Bank normals are normalized geometric source
normals blended 70% face / 30% vertex by the existing compiler. They are not
optical normal maps. Low LOD supports grow with area per sample; their shape
and color remain approximations to the original source.

An additional **38 calibrated orthographic views at 384×384** retain:

| Channel | Meaning |
| --- | --- |
| position_m | Canonical world-space position; NaN outside mask |
| normal_world | Original triangle normal, distinct from bank smoothing |
| color_linear | Original linear vertex RGB, barycentric interpolation |
| depth_m / ray_distance_m | Camera-forward / ray distance in meters; infinity outside mask |
| triangle_id | Original source triangle index; 0xffffffff outside mask |
| material_id / roughness | Original opaque material and source factor 0.6 |
| mask | Explicit first-hit coverage |
| views.json | World-from-camera transform, projection span, pixel convention, SHA |

Views cover three elevations (-60°, 0°, +60°), 12 azimuths and two poles.
Validation observes 419,913 distinct original triangles across the images;
finite sampling is not proof that every triangle appears in an image.
The complete original mesh remains available offline. LIE's surface bank is
sampled from that source, not reconstructed by fusing the PNG previews.
Numeric view reprojection error is below 3.8e-8 m in the local dataset.

## Seeded assembly

`lie_scanned_masonry.py` accepts arbitrary uint32 seeds with repeatable
`--seed` arguments. A versioned integer hash supplies independent variation
by section, row, column and channel. No ambient random state or frame time.
Canonical JSON quantizes floating poses to nine decimal places and carries
seed, dimensions, stable IDs, bank identity, rigid
poses and explicit openings.

The first prototype uses **whole-brick stack bond**, 8 mm nominal joints,
bounded submillimeter jitter and yaw/180° turns. Bricks keep scale (1,1,1),
source color and source roughness. No stretched fake half bricks. A proper
running bond needs a separate half-brick master with an authored cut face.

Doors/windows omit whole brick cells and their mortar. Mortar is captured
authored box geometry recessed behind the source faces; roof/floor are also
explicit simple authored assets. These are not additional scans. Corners are
prototype butt joints, not structural design. Seed variation changes poses
and opening positions within this template; it is not unrestricted architectural
generation. Native UI includes precompiled seeds 2102 and 7319.

| Case, seed 2102 | Bricks | Total instances | Sample invocations |
| --- | ---: | ---: | ---: |
| Individual | 1 | 1 | 480,000 |
| Wall with opening | 84 | 168 | 416,640 |
| House | 2,440 | 4,882 | 2,213,888 |

The assembly bank contains three masters and **46,878,720 bytes**, shared via
the existing RenderingDevice lease cache. Bricks reference bank ranges; no
per-brick upload of the original source. Source meshes are not drawn by the
native camera. The actual source mesh is used only for offline capture and
the separate Blender inspection render.

## Native reconstruction and limits

The lab reuses the existing opaque GGX camera consumer with isolated generated
compute entries. The accepted full-support shadow fix also applies here.
Large authored roof/floor footprints allow a bounded 64-pixel projection
radius instead of the inherited eight-pixel cap. Source-face/depth checks
still run; this is not image dilation over openings.

The new consumer explicitly permits 8,192 instances / 3,000,000 invocations;
legacy consumers retain their previous default budgets. Five LODs use the
same asset-identity and shared-buffer contracts. This prototype chooses LODs
by assembly mode with deterministic budget fallback; continuous screen-error
LOD and frustum/occlusion scheduling remain future work.

Lighting here is the existing point-light GGX plus authored ambient. The
shared indirect field from the independent reference lab is **not integrated
into these generated houses yet**. The legacy GGX dielectric F0 is 0.025;
authored IOR 1.5 is provenance, not an exposed measured/consumed optical
parameter. No claims of measured albedo, refraction, global-illumination
fidelity or a photorealistic finished house follow from these captures.

Local Godot 4.7.2 / Mesa 25.0.7 / llvmpipe LLVM 19 passed 42 real native
checks: finite rendered output, seed changes/restoration, runtime relighting,
transparent wall opening, idle reuse, bank sharing between two active
consumers, safe release and validated atomic commands. Python: 259 tests,
258 passed and one skipped. Rig: 247 checks. Agent session: 25 checks.
CI run **42262987934** at code `fcbbee5d8ce7b8190d28cccdbe815ce180d1cb9d`
also passed 259 Python tests (258 passed, one skipped), 247 rig checks, 25
agent checks and 42 native checks on llvmpipe LLVM 21.1.8. Downloaded CI
evidence matches the local 46,878,720-byte bank and all six canonical recipe
files byte for byte. See the checkpoint for artifact SHA and sizes.

At 720 output / 1440 internal resolution the local house consumer references
46.9 MB shared data plus about 406.6 MB exclusive buffers/textures. This is a
desktop validation configuration, not a low-end mobile target. No Android
FPS, thermals or performance acceptance has been measured. No new APK was
produced in this step.

## Preserved failures

The first local trial exposed sparse house coverage: distant LOD radii were
capped too small, fallback reduced front-wall samples, and large roof splats
were truncated. A separate sharing test incorrectly attached a second world
environment instead of both consumers to the active compositor; its readback
timed out. Those images/logs remain in the dataset failure folder. The accepted
trial enlarges sample supports, declares an explicit higher desktop budget,
uses dense roof/floor capture, and tests actual simultaneous compositor
consumers. The first CPU discovery also lacked the installed trimesh path;
the complete dependency-backed run is the one counted above.

## Reproduce

Install `requirements-ci.txt`. Acquire the authorized original GLB with its
source provenance. Use Godot 4.7.2; Blender 4.3.2 generates the numeric views.

```bash
PYTHONPATH=tools python tools/lie_scanned_brick_prepare.py --source brick.glb --provenance gpu_compute/assets/scanned_masonry/source_provenance.json --output /tmp/scan
blender -b -t 4 --python tools/lie_scanned_brick_views_blender.py -- --capture /tmp/scan --resolution 384
PYTHONPATH=tools python tools/lie_scanned_brick_verify.py --capture /tmp/scan
PYTHONPATH=tools python tools/lie_scanned_masonry.py --capture /tmp/scan --output /tmp/bank --seed 2102 --seed 7319
PYTHONPATH=tools python tools/lie_scanned_masonry_shader.py
PYTHONPATH=tools python tools/lie_scanned_masonry_stage.py --bank /tmp/bank --stage /tmp/native
godot --headless --path /tmp/native --editor --import --quit
godot --path /tmp/native --rendering-driver vulkan --rendering-method mobile --script res://test_lie_scanned_masonry.gd
```

Source attribution and a description of transformations must travel with
redistributed captures and derived assets. CC BY 4.0:
https://creativecommons.org/licenses/by/4.0/ .
