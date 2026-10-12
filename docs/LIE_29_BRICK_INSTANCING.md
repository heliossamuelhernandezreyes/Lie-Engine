# LIE29 — Deterministic brick master instances (phase 1)

**Status: authoring foundation, not yet a rendered LIE29 scene.**

Branch based on LIE28 experimental commit `27a87c4`, not `main`.
This preserves the earlier building laboratory without prematurely merging it.

## Implemented now

- `tools/lie29_brick_layout.py` generates 100 × 100 brick placements by default.
- Each placement references one of 1–3 shared master IDs, never copies a mesh
  or a captured sample buffer.
- Tone and roughness offsets use stable integer hashing of seed, row, column,
  and channel. Identical seeds produce identical results on separate runs.
- Running bond alternates half-pitch offsets; stack bond is also available.
- Explicit dimensional, master-count, and variation validation.
- `tests/test_lie29_brick_layout.py` checks repeatability, spacing, bounds,
  patterns, and 10,000 placements.

## Produce the instance data

```sh
python tools/lie29_brick_layout.py --out /tmp/lie29-bricks.json
python -m unittest discover -s tests -p 'test_lie29_brick_layout.py' -v
```

Default brick physical dimensions: 0.24 × 0.07 × 0.12 m, mortar gap 0.01 m.
The generated running-bond array is 25 m wide before the staggered half-brick
offset and 8 m high; it is a stress layout, not a structurally engineered wall.

## NOT implemented / still to validate

- No cinematic photogrammetry master has been imported or licensed as an asset.
- No LIE29 shader or 10,000-instance GPU scene yet consumes this JSON.
- LIE28 currently uses a finite instance/sample-work budget: feeding all
  10,000 bricks directly into that runtime would exceed its limits.
- No LOD aggregation, GPU culling, draw-batching, cache residency, physical GPU
  benchmark or perceptual comparison against Godot mesh rendering yet.
- No per-brick damage physics, construction joints at staggered wall ends,
  or structural simulation. Edge trimming needs matching half-brick masters.
- Tone and roughness values are data fields; GPU shading implementation is next.

## Next experimental gates

1. Acquire 1–3 redistributable, high-fidelity brick sources; retain their
   exact license/attribution and SHA-256.
2. Capture complete PBR data and evaluate quality at different capture sizes.
3. Add GPU consumption of instance tone, roughness, source-master ID,
   pose, and stable grouping. Make work budgets scale with visible samples,
   not total bricks in the entire world.
4. Benchmark 1, 100, 1,000 and 10,000 instances against conventional meshes,
   reporting visual error, VRAM, GPU timings, and hardware information.
5. Preserve positive and negative results before merging into main.
