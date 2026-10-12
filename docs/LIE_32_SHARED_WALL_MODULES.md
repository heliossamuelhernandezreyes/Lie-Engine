# LIE32 — shared baked wall modules with deterministic variation

## Actual implementation

LIE32 takes the **verified native LIE31** CC0 photographic PBR sample bank
and pre-bakes four distinct modules into immutable sample ranges:

- Each 2.5 m × 0.96 m module visually contains 126 bricks and one recessed
  mortar plane.
- Seed is varied at bake time to change brick tint and roughness *within* each
  module. Additional per-instance tint is applied at runtime.
- Rendering four modules uses **four GPU instances and four sample jobs**,
  not 508 (126 bricks plus mortar per module).
- The source per-brick proxies and detailed PBR master remain available in
  LIE31 for nearby/editable/destructible geometry. LIE32 uses simpler
  shared module collision bodies; it is not yet reversible back to brick-level
  physics automatically.
- Samples from all six brick faces are transformed into module-local 3D
  coordinates, with support bounds moved to the new positions so the
  original per-brick coverage clipping survives.

This is a **baked approximation**, and visual detail must be independently
checked before use in an actual game scene. Reducing GPU invocations does not
automatically prove improved FPS/VRAM.

## Benchmarks and experimental status

- The first prototype (90,528 total sample invocations across four modules)
  rendered via Godot/Vulkan but produced blurry, noisy bricks that nearly lost
  mortar joints. This is a **negative visual result** and is preserved in
  GitHub CI history.
- Revised candidate increases spatial sample density selectively (front,
  mortar and side contours) and reduces footprint inflation to trade some
  work back for higher visual fidelity. Preserve both CI logs and resulting
  native compositor PNGs.
- For comparison, the original LIE31 detailed wall uses **437,306 sample
  invocations for one 126-brick scene**, without extrapolating runtime speed.
- Source PBR CC0 (Poly Haven Red Brick), originally captured in LIE31. The
  underlying dense geometry is height-map-derived rather than a downloaded
  Sketchfab scan.

## Reproduction

```sh
python tools/lie31_restore_hd.py
python tools/lie32_bake_wall_clusters.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab lie32 \
  --directory /tmp/lie32-new
python tools/lie32_native_smoke.py --directory /tmp/lie32-new
```

Once CI publishes a finalized master bank, use
`python tools/lie32_restore_modules.py` instead of re-baking.

## Open work

- Validate closeness to LIE31 at the SAME apparent brick size and viewpoint.
- Measure hardware GPU time, VRAM residency, and scene preparation time
  against the fully instanced LIE31 architecture; current research is CPU
  Vulkan and invocation-count only.
- Tune culling/LOD switching and preserve switching back to individual
  functional bricks near the player.
- Support more than four modules with full occlusion and virtual residency,
  once the material reconstruction quality is acceptable.
