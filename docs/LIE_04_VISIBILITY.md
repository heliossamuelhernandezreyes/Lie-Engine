# LIE-04 — angular continuity and conservative grouped visibility

## Angular presentation
Azimuth is measured in node-local coordinates. Two neighboring views (floor of angle/step, next with wraparound at 360°) are reconstructed from albedo + normals + depth into sampled triangles. Their two opaque shader materials use **complementary 4×4 Bayer masks** to preserve ordinary GPU Z-buffer occlusion, not alpha transparency. At exactly a captured angle, only one mesh is drawn; at 45° between 0° and 90° both have half the screen-space coverage.

This smooths the fractional *coverage change*, not the actual surfaces. Silhouettes can jump, disocclusions/holes and dithering patterns remain visible; high camera angular speeds may shimmer. Elevation samples still select the nearest one. Dual views cost more geometry and texture memory than the single-view mode.

## Visibility BEFORE geometry construction
- Conservative camera frustum: bounding sphere (capture radius times an intentionally larger safety multiplier and node scale) must be completely outside a frustum plane before culling the entire node.
- Authored static rectangle: `scripts/lie_occluder_rect.gd` is a visibility proxy on its local XY plane. Project the 8 vertices of the node's enclosing WORLD-axis cube through the camera onto that plane. If each ray strikes the **inside** of the single rectangle and every vertex is behind the plane, the entire node is conservatively blocked. A partially exposed node MUST remain active.
- The authored rectangle does **not** draw a wall. It must match actual *fully opaque, static, solid* geometry, never glass, gaps, doorways, or moving walls. Failing to match the visual wall will produce incorrect disappearances. The method does not combine partial occluders and is not general hardware Hi-Z.
- Rejected nodes do not request angular views, load image triplets, construct depth triangles, or update their visible surfaces. Visible nodes still let the GPU's regular Z-buffer handle partial overlap.

Node origin must remain at the Blender capture orbit center. Err on the side of a larger conservative radius, or disable manual occlusion for an asset with uncertain bounds.

## Tests
- `tests/test_lie_visibility.gd`: frustum, camera-behind, near plane, full wall, partial wall and crossing-wall tests.
- `tests/test_lie_angular_pair.gd`: midpoint weights, wraparound and angle-boundary continuity.
- `tests/test_lie_04_visibility_pipeline.gd`: whole-node rejection prior to any cached texture or mesh creation, recovery after moving the wall, and preservation of partially visible nodes.
- `tests/test_lie_04_angular_frames.gd`: actual Godot capture with Blender-derived 0°, 45°, 90° views. Tint the two shader passes red/blue to prove both are represented at the midpoint and only one at exact captured angles.

## Not yet implemented or demonstrated
True geometry morphing/reprojection across angles, elevation interpolation, absence of silhouette holes, dynamic multipoint occlusion, GPU-driven Hi-Z, asynchronous mobile texture streaming, mobile frame-time/memory benchmarks. This is a proof of rendering structure, **not** an efficiency or fotorrealism claim.
