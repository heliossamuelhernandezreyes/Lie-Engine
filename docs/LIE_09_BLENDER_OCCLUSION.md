# LIE-09 — real Blender source and Godot-native occlusion

This is the first stage that attempts to show **actual three-channel Blender data** inside Lie's integrated GPU projection and Godot's main compositor. The synthetic sphere is NOT accepted as a substitute in the new test.

## Inputs
- A real generated **GLB** is captured by existing Blender script into per-view RGBA albedo (8-bit), normal (16-bit), depth (16-bit, positive linear orthographic).
- A schema-2 `manifest.json` gives capture radius, orthographic scale and camera depth range. The capture generator produces **4 azimuths × 3 elevations**. LIE-09 currently uses the four 0-degree elevation captures only; elevation selection and streaming are follow-up.
- The startup script resamples **four 128×128 capture sets** to four 64×64 sample grids. This is a CPU startup upload of image arrays, not a GPU-resident PNG decoding or fast atlas streaming. It is performed once, before the render callback.
- The shader reconstructs world positions from Blender camera parameters, projects to a moving Godot perspective camera, checks GPU normal direction **per sample**, weights contributions by view-angle confidence, executes an atomic depth test and writes a persistent RGBA32F texture.
- **Native raster geometry depth** is read via `RenderSceneBuffersRD.get_depth_layer`, sampled through a GPU depth sampler, and linearized from Godot's own view projection matrix. Lie's GPU depth is compared to Godot scene depth for each overlay pixel.

## CI
- Create asymmetric multi-material glTF fixture using actual Blender, capture all 12 views in 3 channels and validate PNG hashes.
- Copy the generated capture bundle into the *separate* `gpu_compute/captures/demo_shard` project, import, then verify Vulkan shader and viewport screenshots at 0° and unseen 35°.
- An unshaded red Godot-native box placed between Lie and the camera must win; when moved behind, Lie must cover it. These are **two independent depth relationships**, not always-native-wins compositing.
- Store screenshots for manual visual inspection. No FPS superiority is claimed.

## Constraints
- Captures are opaque / unlit base colors only, not full PBR, specular, roughness, subsurface, dynamic shadows or relighting.
- GPU perspective projection runs each frame, but four 64×64 resampled source channel arrays come from CPU startup and camera metadata is updated per yaw. No streaming scheduler or LOD.
- Source material color transforms, normal encoding and 16-bit PNG depth require verification on more complex models and real GPU devices.
- 2×2 pixel splatting remains a coverage tradeoff; it can expand silhouettes. A depth gap under 7cm can mix different objects.
- The normal RGB orientation and depth buffer projection convention are validated only by this controlled Blender fixture and one front/rear occluder. A generic camera angle or multiple native transparent/occlusion cases are not yet guaranteed.
- We must still compare frame timings (p50/p95/p99, GPU profile, thermal) on actual Vulkan mobile devices before claiming optimization.

## Local
1. Run the existing `tools/create_lie_fixture_blender.py` to create a test GLB and `tools/lie_capture_surface_blender.py` to create a 4×3×3 channel capture (see workflow for exact commands).
2. Copy `assets/captures/demo_shard` to `gpu_compute/captures/demo_shard`.
3. Open `gpu_compute/project.godot` in Godot 4.7.2 with Forward+/Vulkan. Start the LIE-09 lab, rotate with arrow keys. Missing captures must fail, not silently show a fake object.
