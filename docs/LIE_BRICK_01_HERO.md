# LIE-BRICK-01 — Visible clay brick separated from one invisible box

This experiment is **real LIE engine code**, not an image generator.
The renderer uses the LIE33 software Vulkan compositing shader and 80-byte
sample records; an entire full or half brick consists of **one hidden,
axis-aligned BoxShape3D collision proxy and one independently captured
LIE visual master**. No source mesh or collider triangle soup is displayed.

## Authorship and source transparency

- Input is Poly Haven CC0 `red_brick` 4K photoreal photographed PBR material,
  downloaded via `tools/lie31_acquire_pbr.py`, SHA-256 pinned in
  `evidence/LIE31-source-lock.json`.
- **This is not a downloaded 3D-scanned individual brick mesh.** LIE-BRICK-01
  constructs a geometric full/half brick surface offline using the photographed
  material plus deterministic erosion, not an external sculpt or a photo-only
  shader trick.
- Cavity/edge regions are genuinely displaced by millimeters in the captured
  3D sample positions; adjacent faces share the same chipped spatial corner.
  The GPU never renders those source surfaces as mesh triangles.
- Six faces carry photographic linear-albedo color, 4K roughness and source
  normal map. Normals incorporate gradients of physically displaced positions.
- Cosine-spaced sample grids place more data near edges and corners. Hero,
  medium and distant capture profiles are distinct immutable ranges.
- Support bounds are derived from sample-local face patches to reduce
  smoothing across eroded silhouette contours.

## Native runtime

- `tools/lie_brick01_capture.py`: offline build, two distinct masters, three
  LODs each, UTF-8 catalog + native 80-byte binary bank.
- `gpu_compute/lie_brick01_effect.gd`: LIE33 tiled native Vulkan 1080² GPU.
- `gpu_compute/lie_brick01_lab.gd`: inspection UI and stable agent API;
  *one* BoxShape3D collider per active brick; switch full or half freely.
- `tools/lie_brick01_native_smoke.py`: nonempty original GPU PNG, one collider,
  four photo/light inspection poses, half brick, hero LOD and far LOD.
- Native PNG evidence: `LIE-BRICK01-Front.png`,
  `LIE-BRICK01-ThreeQuarter.png`, `LIE-BRICK01-Top.png`,
  `LIE-BRICK01-RakingLight.png`, and `LIE-BRICK01-Half.png`.
- Captures are 1080×1080 **square**, not 1920×1080 widescreen.

## Reproduce

```sh
python tools/lie_brick01_restore.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /absolute/path/godot \
  --lab liebrick01 --directory /tmp/lie-brick01-run
python tools/lie_brick01_native_smoke.py --directory /tmp/lie-brick01-run
```

To rebuild the real source photographs into LIE geometry:

```sh
python -m pip install numpy pillow
python tools/lie31_acquire_pbr.py --directory /tmp/lie-brick01-source --resolution 4k
python tools/lie_brick01_capture.py --source /tmp/lie-brick01-source
```

## Acceptance gate

**Passing native tests does NOT imply photographic indistinguishability.**
Visual acceptance requires multiple matched camera/light comparisons against
actual photographs of an individual brick, including imperfect silhouettes,
top face, corner chips and raking light. The result is rejected as a hero
quality asset if it still looks like a regular prism, regardless of sample
count. This flag is deliberately `hero_quality_accepted=false` in its catalog.
Physical GPU performance remains to be benchmarked.
