# LIE31-HD — first CC0 photographic surface-capture experiment

## Work in progress and honest source provenance

- **Actual downloaded source:** Poly Haven [Red Brick](https://polyhaven.com/a/red_brick) CC0 4K: real-world photographic albedo, tangent-space normals, displacement and roughness; file SHA-256 values locked at `evidence/LIE31-source-lock.json`.
- **Not yet downloaded:** Sketchfab/kosmoso photogrammetry mesh. That item may require authentication, and must not be substituted without explicitly identifying the replacement.
- **Geometry derivation:** LIE31 builds physically displaced brick face surfaces from the photographic height map and transports source color, normal and roughness. This is *derived* high-density geometry, not an original 282.9K-triangle photographic mesh.
- **Reuse:** The inherited LIE30 running-bond scene is 126 individually tintable full/half bricks, one mortar backing and shared GPU masters.
- **Two capture levels:** a dense close-up master and a lower sample-count version for wall instancing. Both should be validated with native Godot captures. A 4K input photo does **not** mean a native 4K or 1080p compositor output; current compositor emits 512 × 512 unless separately expanded.

## Native evidence

A successful GitHub Actions run is required to call a screenshot a native LIE31 result. Results should be saved to `evidence/LIE31-Wall-Godot.png`, `evidence/LIE31-Brick-Closeup-Godot.png` and `evidence/LIE31-validation.json`. The separately saved `LIE31-SOURCE-Crop-Not-A-Render.png` is explicitly **not** a compositor screenshot.

## Reproduction

```sh
python tools/lie31_restore_hd.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab lie31 --directory /tmp/lie31-test
python tools/lie31_native_smoke.py --directory /tmp/lie31-test
```

To generate from the external public-domain maps afresh:

```sh
python -m pip install numpy pillow
python tools/lie30_restore_bank.py
python tools/lie31_acquire_pbr.py --directory /tmp/lie31-source --resolution 4k
python tools/lie31_capture_hd.py --source /tmp/lie31-source --output gpu_compute/captures/lie31hd
```

## LIE32 planned follow-through

After validating the full-density individual-brick master and 126-brick wall, create *finite seeded variants* of baked wall modules, with a separate per-instance tint/noise seed. A module may reuse one of `K` immutable sample banks rather than baking a unique bank for every wall. Independent comparison of visible sample invocations, VRAM and visual variance is mandatory before making performance claims. Original brick-level logical IDs and collision proxies remain available for switching back to a destructible near-field wall.

## Limitations

- Existing LIE renderer still enforces 128 instances, 750,000 total sample invocations and 512 × 512 output.
- Two levels may lose fine detail in the repeated wall; the dense master is intended for one-object hero closeup.
- Hardware GPU, Android, 1920 × 1080 native output, original downloaded scanned geometry and clustered LOD speedups are not yet established.

## Completed native source-to-compositor experiments

- CC0 real 4096×4096 RGB, normals, height, roughness maps downloaded and SHA-256 verified. Source lock in `evidence/LIE31-source-lock.json`.
- `tools/lie31_capture_hd.py` selected a red brick face from the real wall photograph, rejected excessive grout, reconstructed height-displaced sample positions and transported maps into the unchanged LIE 80-byte sample format.
- Immutable bank: `gpu_compute/assets/lie31/hd_bank.zlib`, `gpu_compute/assets/lie31/catalog.json`, SHA-256 of raw bank `608558a3e33083de0809c18f896001bb44d7216d2a1c9fd52e4a76dfd08eda77` (check against current committed catalog after reruns).
- Full brick: 40,520 hero samples; 3,568 wall samples. Entire bank: 73,214 samples, 5,857,120 bytes, reused by 127 wall instances (126 bricks plus mortar).
- Native software Vulkan wall: 437,306 invocations per frame configuration, deterministic seeded tint and exact repeatability.
- Separate native 960×960 square compositor ran successfully: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38270458144. Unscaled outputs: `evidence/LIE31-Wall-Native-960-Square.png` and `evidence/LIE31-Brick-Native-960-Square.png`. It is neither 1920×1080 nor physically GPU-benchmarked.
- 1080×1080 experiment had an empty PNG and was rejected. It would exceed a typical Vulkan 65,535-workgroup dispatch limit with the current single-dispatch strategy; later tiling/split-compute is required.
- The user-requested photogrammetry scanned **individual 3D mesh** (Sketchfab Kosmoso/Corsicana) is still **NOT** acquired. The delivered source is photogrammetry-derived CC0 PBR surface maps with an independently generated heightfield brick. Future tests should import an authorized truly scanned mesh and benchmark geometric/silhouette fidelity.
