# LIE-06 research status and measured gates

## What the implementation actually changes

- **Multi-view source selection**: camera vector transformed into the node-local frame; dot-product angular similarity to every azimuth/elevation capture, `weight=clamp(dot,0,1)^8`, sort by weight, choose nearest four and normalize weights. Only existing, camera-consistent captures are loaded.
- **Normal confidence (CPU)**: forward reprojection reads Blender-world normal encoded in `RGB`, converts to Lie/Godot Y-up local space and transforms to world; surfaces facing away from the new camera are rejected and glancing surfaces weighted down. The old two-source `lie_reprojection_node.gd` remains unchanged.
- **Target-camera reconstruction**: still computed on CPU using previous `lie_forward_reprojector.gd`, project depth into 3D, software target-depth rejection and vertex-color mesh output. With four captures this may cost **more CPU** than LIE-05; any claim of speedup requires evidence.
- **GPU stage is real but bounded**: dedicated Vulkan Forward+ compute shader in `gpu_compute/shaders/depth_fusion.glsl`. It accepts **four already reprojected candidate samples per target pixel**. It selects nearest depth, discards samples outside 7 cm, and weights compatible albedo by per-surface normal confidence and angular confidence. A separate Godot test executes a real RenderingDevice compute pipeline and reads back pixels. This is NOT full reprojection on GPU and is NOT yet integrated into the runtime scene.
- **C++17**: `native/lie_view_math.hpp` provides compiled angular selection and normalized confidence weights. Its CMake/CTest test is compulsory. There is **no GDExtension** and the renderer still uses GDScript.

## Renderer compatibility

The original project's Compatibility renderer cannot dispatch compute shaders. The GPU test uses an **independent Forward+/Vulkan subproject**. Tests must fail explicitly if Vulkan is unavailable: never mark GPU work successful using a CPU substitute. On mobile, compute driver support and thermal performance must be measured on real devices. Godot documentation warns that device support varies.

## Acceptance

- C++ view-index/wrap test passes.
- GDScript nearest four-view selection, angular wrap and weights test passes.
- GPU Forward+ software Vulkan test passes numerically: nearest red beats far blue, compatible colors blend 25:75, empty stays transparent. Report the selected Vulkan device; software Vulkan verifies semantics, **not phone GPU speed**.
- Blender capture bundle generates exact frames; LIE-05 runs its 45° reference first. LIE-06 reconstructs from four real captured images and reports source hits, CPU ms and threshold silhouette IoU vs the original GLB and prior LIE-05 from precisely the same camera.
- If LIE-06 fails to improve IoU, record the regression honestly and prioritize geometry/capture consistency instead of declaring success. Same-camera IoU remains a rough, threshold-based structural diagnostic, not perceptual image quality.
- No Android benchmark, GPU warping of captured pixels, HZB, safe production synchronization/persistent buffers or streaming is implemented.

## Next serious milestone

1. Merge actual per-source projection to a GPU compute kernel: orthographic unprojection, capture-to-world transforms, target projection and safe depth atomic compaction.
2. Avoid synchronous GPU buffer readback and CPU triangulation when drawing the fused output.
3. Evaluate dense 8/16/32 azimuth captures at genuinely *unseen* camera angles; fix silhouette/extrusion errors before optimizing.
4. Test on supported Android Vulkan phones at controlled thermals; track 1/10/50 nodes and VRAM, p50/p95/p99 latency, render scale and quality.

Benchmark outcomes are hypotheses until CI/devices report them.
