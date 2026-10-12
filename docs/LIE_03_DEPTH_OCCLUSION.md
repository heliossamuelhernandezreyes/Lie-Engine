# Lie Engine 0.3 — sampled depth geometry and actual Z occlusion

## Principle

A captured angle from Blender supplies unlit albedo, world-space normal and camera-axis linear depth (LIE-02). The new `LieDepthMesher` reconstructs a **bounded triangle mesh from those depth samples**; the original glTF mesh is **never rendered by Lie**. A standard Godot `MeshInstance3D` submits triangles to the GPU's real depth buffer, so separately reconstructed nodes are occluded according to their reconstructed **positions**, without painter-style Sprite3D layering.

This is a hybrid baseline, **not** an entirely polygon-free engine: sampled depth meshes still incur vertex processing and can perform worse than original source meshes.

## Transform convention

- Capture source: Blender Z-up -> Lie/Godot Y-up; +Z front.
- Node frame origin **must** be the orbit center used by the Blender capture.
- For each capture camera direction `D`, camera origin relative to node is `D * (4.5 * radius)`.
- An orthographic ray through pixel `(u,v)` begins at camera origin plus `right*(u-.5)*ortho_scale + up*(.5-v)*ortho_scale`.
- Reconstructed sample = ray origin `- D * lerp(near,far,depth)`; `depth=0` is near and `depth=1` far.
- `right,up` are derived from `Basis.looking_at(-D,Vector3.UP)`.
- Node's Godot transform positions/rotates the reconstructed surface into the scene.
- Triangles are rejected at transparent pixels and large depth discontinuities; **this can create holes** near silhouettes. Unseen/back faces cannot be recovered from a single view.
- A conservative grid vertex budget of about 65k vertices per selected view limits 2K captures. Default grid stride=2; no streaming/LRU across assets, FIFO caches 3 views per node.

## Rendering / accuracy limitations

- Standard opaque rasterization depth buffer; **no** manual shader DEPTH write, hardware ray tracing or screen-space depth texture tricks.
- Lighting: normal-map directional Lambert, ambient plus tint, **no cast shadows** or PBR/roughness.
- View changes rebuild/reuse one cached sampled mesh. At nearest-view boundaries, **visible popping** remains possible.
- Each node can be moved and overlapped. Z occlusion is per sampled triangle; not true per-pixel continuous reconstruction, especially between camera angles.
- The synthetic fixture is a nonphotographic sphere-like surface. CI also tests with an original Blender-produced glTF (12 directions, 128 px).
- The "object reference" inside LIE-02 does not establish quality, speed, memory or fidelity superiority.

## Acceptance requirements

1. Verify `pixel_position` at known orthographic coordinates, depth changes and alpha masks with pure Godot tests.
2. Validate two independently moving rigid nodes whose sampled meshes are nonempty and never draw the original source model in normal mode.
3. Capture opposite camera positions from the **same scene**, with red and blue object tints, assert foreground pixel color switches appropriately (not just hash mismatch).
4. Blender CI imports a real triple capture and validates all PNG hashes as well as the runtime mesh.
5. Benchmark in the same Godot build and phone before any 60 FPS or efficiency claims.

Nothing here is a completed high-performance mobile renderer.
