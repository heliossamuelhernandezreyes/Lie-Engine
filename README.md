# Lie Engine — LIE-01 through LIE-08

**Research prototype, not a proven faster renderer.** Lie separates an invisible 3D world (physics and spatial transforms) from a camera-indexed image-based visual layer.

Lie is developed **on Godot 4.7.2**; its asset addressing and capture pipeline are kept independent of individual game projects. ARCONT can serve as an external testing/research laboratory, not as embedded game code.

## LIE-08 — active GPU viewport laboratory (experimental branch)

The *separate* `gpu_compute/` Godot Forward+ project now has `lie08_lab.tscn` as its startup scene. Open that project in Godot 4.7.2 with Vulkan, press **Play** and use left/right arrows to orbit a procedural spherical source. The same global RenderingDevice computes four-view depth projection, z-buffer confidence fusion and an RGBA32F image, and a CompositorEffect displays it directly in the Godot viewport without a CPU image readback or 3D mesh reconstruction each frame. The sphere is a **mathematical fixture, not a Blender asset**.

LIE-08 adds screenshot CI validation at 0° and 35°, including a missing-pixel coverage check. The original project `project.godot` still starts the previous CPU LIE-06 lab and stays unchanged. Read [LIE-08 GPU viewport limitations](docs/LIE_08_VIEWPORT.md), especially the lack of Godot-native depth testing and mobile FPS evidence.

## LIE-06 — multi-view reference + real Vulkan GPU kernel (default in original project)

The startup scene `scenes/lie_06_lab.tscn` reconstructs a target-camera surface from **up to four nearest azimuth/elevation captures** with angular confidence. When per-pixel normal data is available, samples facing away from the current camera are rejected and grazing angles are attenuated. **Arrows** move the camera; **Space** reprojects on CPU.

A separate **`gpu_compute` Forward+ Vulkan project** runs an actual compute shader that fuses up to four **already projected candidates** per target pixel according to nearest depth, surface confidence and angular weight. This step is really executed on the GPU in CI; the complete projection step remains on CPU in the visible lab. Do not confuse the working GPU compute proof with a fully GPU-driven renderer.

A second Vulkan compute shader `gpu_compute/shaders/project_samples.glsl` performs **per-sample depth unprojection and projection into the current perspective camera**, checked numerically for centered, offset and clipped samples. Its output is not yet connected to the renderer's full screen-space scatter.

The `native/` directory contains a C++17 angular selector, compiled and verified by CTest. It is **not yet wired through GDExtension** into Godot. Production mobile speed, reliable continuous crossfade and silhouette improvements are still unproven; read [Lie 0.6 research gates](docs/LIE_06_RESEARCH.md).

## LIE-05 — target-camera depth reprojection (earlier lab)

The previous scene is `scenes/lie_reprojection_lab.tscn`: rotate the camera with **left/right**, then press **Space** to reconstruct the new view. Two captured angular images are unprojected into 3D, reprojected into the current perspective camera, and fused using a software nearest-depth test (world-space points, bounded 2×2 splats, depth-consistent albedo weighting). The output is a **real 3D surface reconstructed from images**, participating in Godot's ordinary Z-buffer. The original GLB geometry is never rendered in Lie mode.

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
3. LIE-06: arrows move the camera; **Space** rebuilds a four-source CPU reprojection. LIE-04 remains available from `scenes/lie_depth_lab.tscn`.
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
