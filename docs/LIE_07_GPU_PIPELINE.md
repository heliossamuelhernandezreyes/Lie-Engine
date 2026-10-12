# LIE-07: joined GPU forward reprojection experiment

This branch intentionally builds on LIE-06. It adds one Vulkan compute program with five GPU dispatch stages and explicit memory barriers:

1. Clear per-target-pixel minimum depth and fixed-point color accumulators.
2. Reproject multiple independently parameterized orthographic depth samples into a target perspective camera **on GPU**.
3. Atomic minimum positive IEEE-754 depth per target pixel (1x1 or 2x2 splat).
4. Accumulate only samples within 7 cm of the nearest depth; weight source RGB by precomputed normal and angular confidence.
5. Resolve to **RGBA32F GPU storage image**, with transparent pixels where no valid sample survived.

A new mandatory CI test verifies four source transforms, visibility/frustum rejection, nearest-depth rejection, zero-normal-confidence rejection, expected 25%:75% color mixing and transparent holes. It submits the five compute stages together; there is **no GPU-to-CPU readback between stages**. The one final texture readback is **test-only**.

## Important non-claims / engineering limitations

- The test uses a local Godot Vulkan RenderingDevice. The **main Lie-06 Godot Compatibility visual scene still uses CPU**. A local device texture is NOT directly visible in the main Godot viewport. Integrating the pipeline into Godot's global render device (e.g. via CompositorEffect or suitable RenderingServer hooks), without readbacks, is subsequent work.
- Data upload and angular/normal confidence derivation still occur on CPU. Blender albedo/depth/normal atlases are not yet streamed as GPU image resources. No texture cache, persistent per-frame GPU allocations or adaptive quality is implemented.
- Simple atomic minimum + depth-tolerant weighted accumulation is not exact triangle visibility, does not repair disocclusions, and can mix distinct surfaces within the 7 cm depth band. Accumulation is non-HDR RGB [0,1] fixed-point; the total weight **must stay well below 2^32** to avoid integer overflow. Camera transforms must use normalized orthogonal bases. Source depth maps must represent metric-linear orthographic depth.
- This is a numerical proof under software Vulkan; performance, memory, visual quality and mobile driver support **remain unmeasured**. The isolated LIE-06 shaders and their tests remain intact.

## Next gate
Move the same GPU pass into a Forward+/Mobile renderer-visible compositing path, supply real captured textures via persistent GPU resources, add normal confidence on GPU, and compare 1/10/50 objects with raster geometry and CPU reference at matched 720p/1080p on real devices. Fail on disocclusion, ghosting and memory regression rather than hiding them.
