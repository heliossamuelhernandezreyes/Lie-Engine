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

## Verified native release: second sampling candidate

- CI workflow native 512 run: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38271487796
- Actual 512 output: `evidence/LIE32-Cluster-Wall-4Modules.png` and `evidence/LIE32-Cluster-One-Module-Closeup.png`.
- Native high-res 960 × 960 run: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38271835997
- Actual high-res: `evidence/LIE32-4Modules-Native960.png` and `evidence/LIE32-Module-Detail-Native960.png` with SHA-256 report.
- Native 4-module output: **4 compositor instances, 504 underlying brick appearances, 394,880 invocations**. Each of four reusable variants has 98,720 samples; sample bank total 394,880 samples = 31,590,400 uncompressed bytes.
- The original fully instanced LIE31 single wall requires 437,306 invocations per wall, so four copies would naïvely request 1,749,224 (well beyond its per-scene cap). This is a count comparison only, NOT a measured physical-GPU speedup.
- Images show that higher-resolution output substantially improves legibility. The 960px single-module screenshot makes joints readable; the four-module view still exhibits aliasing and reduced surface fidelity compared with individual LIE31 samples. Do not claim visual parity.
- Four pre-baked module variants consume more source-bank storage than one common brick; this is an explicit VRAM-vs-invocation tradeoff. Hardware validation is needed.
