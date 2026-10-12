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

## Tested LIE-BRICK01 version 3 — native Vulkan (2026-10-12)

**Actual execution:** https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38323231074

- Fixed a real LIE22 compatibility blocker: the unchanged base sampler rejected
  any master with three LOD levels. The branch accepts legacy 2 or new 3 LODs.
- Original PBR photo-derived, edge-weighted six-face source captures:
  `brick_full` **258,990 hero / 36,358 middle / 5,173 distant** samples;
  `brick_half` **202,680 hero / 29,134 middle / 4,182 distant** samples.
- Immutable bank SHA-256:
  `5b585ccacefd63845804a651432c0234a578eb0ac335d54f6f425b3890c4f987`.
  Includes 12 sample-only curved edge bridges per master/profile.
- One invisible `BoxShape3D`, one visible LIE compositor master; 0 visible
  mesh triangles. Verified native GPU original 1080×1080 per-view pixels:
  `evidence/LIE-BRICK01-Front.png`,
  `evidence/LIE-BRICK01-ThreeQuarter.png`,
  `evidence/LIE-BRICK01-Top.png`,
  `evidence/LIE-BRICK01-RakingLight.png`,
  `evidence/LIE-BRICK01-Half.png`.
- 3 LOD switches and one-box collider checked by native workshop agent.
- First version had unacceptable dotted surface holes due to nonuniform
  sampling with uniform footprint; preserved
  `evidence/LIE-BRICK01-V1-Top.png`.
- Second version fixed the holes by a per-sample geometric footprint,
  but exposed a dark border at six-face seams, preserved as
  `evidence/LIE-BRICK01-V2-Top.png`.
- Third version adds 12 curved edge bridge surfaces sampled directly into the
  LIE bank. Native tests pass. A residual dark/artificial bevel remains under
  grazing light; flat-face appearance is still too uniform.

**HERO VISUAL ACCEPTANCE: FAILED / OPEN.** These GPU pictures are authentic
but still visibly synthetic. More samples alone did not establish photo
indistinguishability. A genuinely photogrammetry-scanned individual brick
with its own multi-face photo textures, a matched reference photograph
and improved microgeometry reconstruction are required before signoff.
A passing smoke test is not a photo-realism benchmark.
