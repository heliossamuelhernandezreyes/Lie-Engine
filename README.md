# Lie Engine — LIE-01 through LIE-05

**Research prototype, not a proven faster renderer.** Lie separates an invisible 3D world (physics and spatial transforms) from a camera-indexed image-based visual layer.

Lie is developed **on Godot 4.7.2**; its asset addressing and capture pipeline are kept independent of individual game projects. ARCONT can serve as an external testing/research laboratory, not as embedded game code.

## LIE-05 — target-camera depth reprojection (current default)

The default scene is now `scenes/lie_reprojection_lab.tscn`: rotate the camera with **left/right**, then press **Space** to reconstruct the new view. Two captured angular images are unprojected into 3D, reprojected into the current perspective camera, and fused using a software nearest-depth test (world-space points, bounded 2×2 splats, depth-consistent albedo weighting). The output is a **real 3D surface reconstructed from images**, participating in Godot's ordinary Z-buffer. The original GLB geometry is never rendered in Lie mode.

The code is a deliberately **CPU-heavy research reference**, not a live mobile renderer. Frame-by-frame synthesis has not been made efficient. On a fresh checkout without Blender assets, the lab visibly uses a clearly labeled synthetic fixture rather than hiding an empty scene. Capture a real `assets/captures/demo_shard` bundle with the Blender 4.x command below, reopen/import in Godot, then the lab uses real depth captures. Read [LIE-05 protocol and limitations](docs/LIE_05_REPROJECTION.md).

## LIE-04 — angular coverage and visibility before reconstruction (older lab)

The older scene `scenes/lie_depth_lab.tscn` uses **two neighboring angular reconstructions** with complementary 4×4 Bayer screen masks. It gradually adjusts their coverage with camera azimuth while preserving Godot's normal Z-buffer. This is dithered coverage, NOT physically continuous view synthesis. Elevation remains nearest-sample.

Before loading textures or generating triangles, groups fully outside camera frustum or conclusively hidden by **authored opaque rectangular occluders** may be omitted. The occluder must correspond to a real fully opaque wall. See [LIE-04 technical contract](docs/LIE_04_VISIBILITY.md).

## LIE-03 — depth reconstructed visibility (earlier stage)

The startup `scenes/lie_depth_lab.tscn` loads **two overlapping Lie nodes**. Their visible triangles are reconstructed from the captured depth channels; the actual source glTF geometry remains absent from normal drawing. The usual Godot depth test now handles inter-node occlusion. Arrow keys orbit and Space changes the illumination tint. Geometry reconstruction is a CPU baseline, not yet an optimization.

See [LIE-03 research protocol](docs/LIE_03_DEPTH_OCCLUSION.md). Depth holes and memory-performance limitations remain unresolved.

## LIE-02: three-channel surfaces (older lab)

The older LIE-02 scene is `scenes/lie_surface_lab.tscn`: it displays a rigid camera-indexed sprite with **albedo + per-pixel normal + normalized depth**, an invisible physical collider, a bounded **parallax approximation**, and **single-source local diffuse lighting**. Arrows orbit the camera, **Space** switches warm/cool illumination. No per-pixel depth writeback, shadows, or real 3D scene reconstruction are claimed.

To generate real textures instead of synthetic fallback, use Blender 4.x:

```sh
blender --background --python tools/lie_capture_surface_blender.py -- \
  --input /absolute/source.glb --out assets/captures/demo_shard \
  --azimuth-steps 16 --elevations=-30,0,30 --resolution 512
python tools/validate_lie_surface.py assets/captures/demo_shard
```

Each angular code receives `.albedo.png`, `.normal.png` and `.depth.png`. Current capture supports opaque Principled glTF materials; check `docs/LIE_02_SURFACE.md` for constraints. CI creates a synthetic original GLB with Blender, captures all three channels, imports them into Godot, and records matched-camera Lie versus original-geometry images.

The previous LIE-01 lab is still available at `scenes/lie_lab.tscn`.

## Run

1. Install Godot 4.7.2 stable (Compatibility renderer).
2. Open `project.godot` and run the main scene.
3. LIE-05: arrows move the camera; **Space** requests a new CPU reprojection. LIE-04 remains available from `scenes/lie_depth_lab.tscn`.
4. Observe the two source angular codes, number of triangles and CPU build time. The original source mesh is never drawn during Lie rendering. Earlier labs demonstrate independent invisible `StaticBody3D` collisions.

The placeholder deliberately is **not** a photographic asset. The first capability being tested is: **the same 3D object position deterministically retrieves one angular image at a time, without displaying a source 3D mesh.**

## Produce actual views with Blender

Requires Blender 4.x and a model in glTF/GLB format:

```sh
blender --background --python tools/lie_capture_blender.py -- \
  --input /absolute/path/to/model.glb \
  --out assets/captures/demo_shard \
  --azimuth-steps 16 --elevations=-30,0,30 --resolution 512
```

Reopen the Godot project to import the generated PNGs. Their stable paths are `assets/captures/demo_shard/az_00_el_00.png`, etc. The demo then loads these instead of placeholders, selecting the nearest angular view.

The older LIE-01 capture script writes **RGBA only**. The separate LIE-02 capture pipeline produces normal/depth images. Coherent PBR shadows, character animation, atlas batching and measured mobile performance are not implemented.

## Validation

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_view_index.gd
godot --headless --path . --script res://tests/test_invisible_proxy.gd
godot --headless --path . --quit-after 30
```

GitHub Actions checks angular selection, depth reconstruction, visibility rejection and multi-view GPU frames. Passing checks are NOT evidence of higher quality or Android FPS.

Read [architecture and research gates](docs/ARCHITECTURE.md).

## Licensing

The project is publicly readable. **No software distribution license has been selected yet**. Do not assume public availability permits redistribution of code. Independently sourced Blender assets retain their own licensing requirements.
