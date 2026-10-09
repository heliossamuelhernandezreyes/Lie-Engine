# Lie Engine — architecture and evidence gates

## Hypothesis

For some mobile scene classes, a *camera-indexed image-based surface* may provide greater visual detail than conventional 3D geometry at equal device memory and frame-time budgets. This is **unproven**. Lie does not assume that textured billboards outperform GPU rasterization.

## LIE-01 contract: one grouped rigid node

- Logical authority: Godot `Node3D` frame and invisible `StaticBody3D`/collision shapes.
- Visual: at most **one active Sprite3D texture per rigid Lie node**, selected by view key.
- Key is derived from **camera minus node world location**, transformed by the inverse node rotation, not world-origin coordinates.
- Convention: node-local **+Z front = azimuth zero**, +X = 90 degrees, +Y up.
- Sampling: equally spaced azimuth indices; user-specified elevation degrees. Nearest angular neighbor. Keys `az_XX_el_YY`.
- No arbitrary XYZ exact-match lookup: continuous positions cannot yield a finite exact photographic image library.
- Anchor node origin must coincide with the **capture orbit center** of the visual asset (the demo positions it at the capsule midpoint). Angular selection must not accidentally use the actor's feet.
- Node remains rigid for this gate. Hierarchical parts, overlaps, skeletal attachment and depth compositing are later capabilities.
- Texture fallback is deliberately synthetic; it only makes selection behavior visible.

## Capture convention

`tools/lie_capture_blender.py` imports a model, determines fixed world-space bounds, orbits an orthographic camera at each sampled direction and writes stable PNG filenames and metadata. Imported models should be authored **upright with +Z front and +Y up in glTF space**. The capture script explicitly maps that Y-up direction into Blender's Z-up coordinates before positioning the capture camera.

The Blender material appearance is captured with lighting baked into RGBA. This is not yet the eventual Lie Surface representation. Correct dynamic relighting will require raw albedo, per-pixel normals in an explicitly documented coordinate space, depth, material metadata, and composition/occlusion policies.

## Next gates (do not claim implemented)

- **LIE-02 (experimental implementation):** capture + validate alpha/albedo, camera-normalized depth and Blender-world normals, camera matrices and near/far conventions; one-source diffuse relighting and bounded UV parallax. **True reconstruction across unseen angles is NOT yet demonstrated.**
- **LIE-03 (experimental):** reconstruct sampled 3D triangles from Blender depth; GPU Z-buffer tests overlap of independent nodes. This is a geometry-based research baseline, **not** accurate per-pixel depth at unseen camera angles or an efficiency claim.
- **LIE-04 (experimental):** neighboring azimuth views composited with complementary dithered GPU coverage; conservative frustum and authored rectangular-wall occlusion before texture loading. This is NOT true novel-view synthesis or generalized Hi-Z occlusion.
- **LIE-05 candidate:** physically coherent lighting, shadows/weather, generic GPU occlusion and reprojection without gaps.
- **LIE-06 candidate:** atlas, texture compression, memory-aware cache, background streaming and device-performance evidence.
- **LIE-07 candidate:** modular animation and skeletal composition.

## Experimental protocol

Always compare against an equivalent **visible 3D mesh** in the *same Godot version, renderer, camera, resolution and phone*. Track frame-time p50/p95/p99, RAM/VRAM, loading time, storage size and visual errors (silhouette discontinuity, shading, disocclusion). Warm-up, cache state and scene visibility must be reported. No results in this repository yet establish superior quality or speed.

ARCONT may validate external results; Lie owns its own scene and assets. Nothing in this repository modifies ARCONT, Fisura or other games.
