# LIE-08 — a GPU-produced surface inside the actual Godot viewport

Unlike LIE-07's isolated local Vulkan RenderingDevice, this stage uses **RenderingServer.get_rendering_device()** inside **CompositorEffect._render_callback** (Forward+).

It reuses the *unchanged, tested* `lie07_pipeline.glsl`: clear -> per-source-sample 3D projection -> nearest depth atomics -> confidence-weighted fusion -> persistent RGBA32F texture. A second compute shader reads that texture and writes it to `RenderSceneBuffersRD.get_color_layer(view)` in the **same GPU command list**. Explicit compute barriers separate stages and the color buffer is never read back to CPU in normal rendering.

The `lie08_lab.tscn` scene orbits with the arrow keys; each yaw is packed into the four source camera records and sent to a small camera parameter GPU buffer. All captured *sample* buffers are retained across frames, so they are not reuploaded every orbit movement. Compositor effects use the main Forward+ renderer; Godot Compatibility cannot use this path.

**Fixture truth:** this stage generates four 64×64 arrays analytically from a colored sphere in GDScript at startup. These are NOT Blender renders, not streamed depth atlases and not the user's game assets. They exist to verify global Vulkan device interoperability, camera motion and actual viewport visibility. We do NOT assert photo-realism, FPS advantage or completeness of geometry.

## CI gate
The CI task renders two real Godot viewport captures at 0 and 35 degrees, requires visible blue center against empty background, requires real GPU callback execution, and rejects unchanged screenshots. Generated PNGs are uploaded as GitHub Actions artifacts. Prior GPU/C++/geometry tests remain mandatory.

## Future
Replace the synthetic source arrays with the actual Blender `albedo/depth/normal` captures and GPU-side normal filtering. Reconstruct only visible screen-space pixels, add source atlas residency/LOD, depth discontinuity repair and animation. Test depth interoperation with native rasterized occluders; current composition overlays scene colors and does **not** depth-test against actual Godot camera depth, so native geometry can be wrongly covered. Compare p50/p95/p99 render times and thermals on Android Vulkan hardware before speed claims.

## Quality gate
Each source depth point writes a bounded 2×2 target splat to avoid subpixel raster holes. This can expand object silhouettes; it is a provisional research tradeoff, not depth-aware antialiasing. The CI evidence requires over 80% coverage of an interior 30-pixel-radius disk at both tested orbits. Future steps should replace rectangular splats with joint bilateral upsampling and discontinuity-aware coverage.
