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
