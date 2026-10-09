# Lie Engine — LIE-01

**Research prototype, not a proven faster renderer.** Lie separates an invisible 3D world (physics and spatial transforms) from a camera-indexed image-based visual layer.

Lie is developed **on Godot 4.7.2**; its asset addressing and capture pipeline are kept independent of individual game projects. ARCONT can serve as an external testing/research laboratory, not as embedded game code.

## Run

1. Install Godot 4.7.2 stable (Compatibility renderer).
2. Open `project.godot` and run the main scene.
3. The camera automatically orbits a **procedural placeholder**. Press the left/right arrow keys to accelerate or reverse its orbit.
4. Observe the changing `az_XX_el_YY` index. Physics uses a separate invisible `StaticBody3D`.

The placeholder deliberately is **not** a photographic asset. The first capability being tested is: **the same 3D object position deterministically retrieves one angular image at a time, without displaying a source 3D mesh.**

## Produce actual views with Blender

Requires Blender 4.x and a model in glTF/GLB format:

```sh
blender --background --python tools/lie_capture_blender.py -- \
  --input /absolute/path/to/model.glb \
  --out assets/captures/demo_shard \
  --azimuth-steps 16 --elevations=-30,0,30 --resolution 512
```

Reopen the Godot project to import the generated PNGs. Their stable paths are `assets/captures/demo_shard/az_00_el_00.png`, etc. The demo then loads these instead of placeholders, selecting the nearest angular view.

Capture script currently writes **RGBA only** (with baked lighting) and a manifest. True per-pixel depth, normal maps, physically consistent lighting, animated pose composition, atlas batching, occlusion and mobile performance are **future experiments**, not implemented features.

## Validation

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_view_index.gd
godot --headless --path . --script res://tests/test_invisible_proxy.gd
godot --headless --path . --quit-after 30
```

GitHub Actions runs these smoke checks for new changes. Success validates import and view-index logic, **not** image quality or Android FPS.

Read [architecture and research gates](docs/ARCHITECTURE.md).

## Licensing

The project is publicly readable. **No software distribution license has been selected yet**. Do not assume public availability permits redistribution of code. Independently sourced Blender assets retain their own licensing requirements.
