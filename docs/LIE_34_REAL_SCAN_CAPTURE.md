# LIE34 — Genuine high-poly Draco photogrammetry into LIE samples

**Source is genuinely photogrammetric 3D geometry, not a reconstructed
heightfield.** The input is a *scanned commercial building with brick facades*;
it is **NOT** one individually scanned brick. Never pass it off as a brick
master for a modular wall.

## Original and provenance

- Project: [Drone Building Scans](https://github.com/Matt1Up/drone-building-scans-dataset)
- Artist: Matthew Guertin, 2026.
- License: Creative Commons Attribution 4.0; credit required.
- Source: `https://huggingface.co/datasets/Matt1up/drone-building-scans/resolve/main/flat-roof/model/flat-roof.glb`
- Original GLB SHA256:
  `6c712d16b9ede8f5083d7fc82787cf75b913865b157f48db08a61f2154c6bd73`
- Original bytes: 21,822,576.
- **2,994,426 vertices / 5,500,320 triangles**, verified after real
  Draco decompression. Original normal and UV streams recovered.
- Original diffuse atlas **8192×8192** pixels.
- `KHR_draco_mesh_compression` is required. Standard trimesh, without a
  Draco decoder, produced all-zero placeholder coordinates: a documented
  **negative source-inspection result**. DracoPy decoded correct bounds.
- Original license and evidence: `evidence/LIE34-original-scan-license.json`
  and `evidence/LIE34-original-scan-metadata.json`.

## True geometry capture

`tools/lie34_capture_real_scan.py` opens the compressed GLB, decodes Draco
triangles, samples actual physical surface positions by triangle area,
interpolates source vertex normals and UVs, samples the real photo atlas,
converts sRGB to linear reflectance and writes the standard 80-byte LIE
format, with face support and near/far masters.

Captured source mesh does not appear as a rendered mesh in the native scene.
The bank is compressed into `gpu_compute/assets/lie34/scanned_facade_bank.zlib`,
with checked SHA-256 in `gpu_compute/assets/lie34/catalog.json`.

### Distinct quality tests

- v1: 140,000 close-range and 42,000 far-range samples, 14.56 MB bank.
  Native 1080-square Godot proof existed but was very patchy; this is a
  **negative result for visual quality**, not a failed source import.
- v2: 540,000 close-range and 120,000 far-range samples, 52.8 MB bank,
  within LIE's 64 MiB immutable sample-library cap and 750,000
  per-render work cap.
- Camera distance `distance_factor>=1.5` selects the far-range bank
  automatically; zooming closer switches to the 540,000-point bank.
- Full visual acceptance requires comparing actual native LIE GPU PNGs,
  not screenshots of the external source or image-generated mockups.

## Reproduce from a verified local sample bank

```sh
python tools/lie34_restore_scan.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab lie34 \
  --directory /tmp/lie34-replay
python tools/lie34_native_smoke.py --directory /tmp/lie34-replay
```

To reproduce directly from original source:

```sh
python -m pip install numpy pillow trimesh DracoPy
python tools/lie34_scan_acquire.py --directory /tmp/lie34-input
python tools/lie34_capture_real_scan.py \
  --source /tmp/lie34-input/flat-roof-reference.glb
```

## What LIE34 does NOT demonstrate

- It does not capture an independent Kosmoso or SMU individual-brick scan.
  Those downloads are listed under artist CC BY but still need authorized
  acquisition or a legitimately provided original model.
- It does not establish source geometry reconstruction quality parity:
  most original triangles are omitted from the sampled representation.
- No measured performance on physical AMD/NVIDIA/Android GPU yet.
- A full-building scan is not a reusable brick. For modular construction,
  continue to use the LIE31 individual brick + LIE32 baked-wall structures
  until a licensable true individual scan can be ingested.
- 1080×1080 is square output, not widescreen 1920×1080.

All source author/attribution must accompany any redistribution or product
using this CC BY scan.
