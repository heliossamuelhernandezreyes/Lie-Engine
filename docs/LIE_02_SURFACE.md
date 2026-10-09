# LIE-02 — triplet surfaces and local light (experimental)

The LIE-02 scene is `res://scenes/lie_surface_lab.tscn`. LIE-01 remains intact.

Each capture view uses **three** texture files sharing the same angular code:

- `az_00_el_01.albedo.png` — RGBA base color + silhouette alpha (prefer unlit diffuse color).
- `az_00_el_01.normal.png` — RGB normals in **Blender/world axes**, encoded `(n+1)/2`; sample in linear space, transform `(x,z,-y)` into Lie's +Y up.
- `az_00_el_01.depth.png` — normalized, positive camera-axis depth: `0=near, 1=far`. Background alpha 0. Camera pose, orthographic scale, near/far, and bounds must be in the manifest.

The Blender 4.0 CI fixture uses explicit source material replacement for each pass: image hashes alone cannot prove color/normal/depth are distinct. The manifest validator additionally rejects identical normal/depth PNGs. Human inspection of channels is still required.\n\nThe shader calculates a *bounded* parallax-style UV offset from the residual difference between an actual camera angle and its nearest sampled angle. It does **not** reconstruct true 3D coordinates, repair newly exposed surfaces, or write per-pixel camera-space depth. Overlapping Lie nodes and geometry may sort incorrectly; accurate depth composition belongs to LIE-03. Lighting is a single directional **Lambertian** approximation based on captured normal, plus ambient. No cast shadows, reflection, roughness, light occlusion or physically based BRDF yet.

Without imported Blender captures, all channels are generated **synthetically** and labelled as such. These prove that channel loading, selection and color-based relighting work; they are not a quality demonstration.

Native acceptance checks channel presence, proxy/mesh separation, unchanged camera light A/B framebuffer pixels and angular selection. Visual differentiation cannot prove relighting quality. Blender asset capture and format validation are tracked independently, and physical Android FPS remains unmeasured.

The visible box labelled Reference3D is deliberately *hidden* for normal Lie execution. Turning it on for A/B benchmarking must hide the Lie visual and match materials, framing, and device settings before comparing results.
