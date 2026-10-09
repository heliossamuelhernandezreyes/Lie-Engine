# Lie Engine 0.5 — target-camera forward reprojection (CPU reference)

## What is actually implemented

Lie 0.5 reconstructs **individual 3D points from 2 neighboring depth captures**, projects them into a target 3D camera's current perspective projection and combines them using a **nearest-depth test**. It does not use the original 3D object's source geometry in the Lie draw path.

1. From each Blender angular capture, decode RGBA and orthographic depth using the manifest's radius, orthographic scale, near/far and sample direction.
2. Convert each foreground source texel into a **node-local 3D point**, then into world space using the real node transform.
3. Project the world point into the CURRENT user's perspective camera using Godot camera projection. Reject points behind camera/near/far.
4. Map the camera pixel coordinate into a bounded 128² target crop around the node, and forward-splat a limited 2x2 area.
5. Compare each target cell's camera-axis depth. The closer surface wins; colors are blended using angular proximity only if they agree within a 7 cm camera depth tolerance. Behind-foreground samples are rejected; not crossfaded into foreground.
6. Build a triangulated **target-camera** mesh from occupied cells. Reject triangles crossing depth discontinuities. The output retains 3D vertex positions and vertex colors and uses the ordinary GPU Z-buffer with other Godot scene geometry.

This is materially different from the LIE-04 two-view Bayer masks: it **reprojects geometry into the current view**, where adjacent captures can fill previously unobserved gaps, and depth consistency determines blending rather than a screen-space red/blue mask.

## Hard limitations

- This is explicitly a **CPU research implementation**, not optimized for mobile or continuous camera animation. Its work scales with input source texels, target pixels, reconstruction and scene motion. Default lab rebuilds only when Space is pressed; moving the camera without rebuilding shows stale reprojection.
- It reconstructs ONLY recorded surfaces; neither captured view can reveal genuinely unknown/disoccluded geometry. Holes remain, and 2x2 forward splatting may hide small ones but is not a general hole-repair algorithm.
- It uses **vertex colors** from captured unlit albedo. Per-texel normals are not reprojected in this baseline, so dynamic physically coherent relighting remains unimplemented here (LIE-04 branch remains available for its earlier relighting experiment).
- The target mesh is still polygonal, may be less efficient than a conventional Godot 3D mesh, and could contain discontinuities or inaccurate triangles between two sources.
- Selected elevation remains nearest captured view, and 2 views may give insufficient coverage at high elevation or complex geometry.
- Size of target crop is calibrated for the experimental camera and fixture, not an adaptive screen-space bounding volume; mobile quality is unknown.
- No real-time mobile FPS, GPU timings, memory comparisons, production streaming or automatic occlusion culling are measured for this prototype. The earlier Lie 0.4 culling remains a **separate path**, not integrated into this CPU target-view rebuild.

## Reproduction and evidence

When working from a repository without generated assets, build the Blender 4.x channels first (see README). To test a real captured asset in Godot, set `azimuth_steps=4` for the CI fixture or export 16 azimuths for the normal lab.

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script res://tests/test_lie_05_forward.gd
# After Blender capture + Godot import:
xvfb-run -a godot --path . --script res://tests/test_lie_05_blender_reprojection.gd
```

The CI native frames at 0°, 45°, 90° are exported as an artifact. They demonstrate novel camera pose projection and visible geometry, **not** similarity to an unseen-angle ground truth or an improvement over conventional rasterization. The next necessary experiment is matched-camera comparison with the source mesh at unseen angles, with quantitative silhouette and occlusion error.
