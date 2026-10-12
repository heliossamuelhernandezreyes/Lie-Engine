# LIE29 native brick-wall laboratory — stage 2

This is real Godot/LIE compositor code, **not** a generated picture.
The test creates 120 individually transformed samples-based brick instances
from the single CC0-attributed LIE28 brick master. Original meshes are never
drawn. Each logical brick has a hidden StaticBody3D/BoxShape3D collision proxy
sharing one BoxShape3D resource.

- Running bond: 10 columns by 12 courses, brick pitch 0.25 × 0.08 m.
- A deterministic integer hash (same coefficients as the Python authoring tool)
  controls one of three tint palettes, tone, and roughness deviation per brick.
- Samples remain GPU resident and are **not copied per brick**. The 120 LOD1
  sample ranges total 678,000 invocations, below LIE22's 750,000 budget.
- The existing 128 instance limit is intentionally preserved. This is *not*
  10,000 concurrently GPU-rendered bricks and does not establish scalability.
- One LIE28 master of procedural geometry/material is used. Photogrammetry
  cinematographic assets have not yet been acquired.
- The shader is a separate LIE29 copy of the LIE28 shader with just a
  per-instance roughness offset addition, preserving source albedo and normal
  capture transport.

## Launch with the actual asset bank restored

Restore the compact CC0-attributed LIE28 brick subset shipped in the repository.
The restore script verifies exact bytes and SHA-256 before writing the native bank.

```sh
python tools/lie29_restore_bank.py
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab lie29 \
  --directory /absolute/path/lie29-live
python tools/lie_workshop_client.py --directory /absolute/path/lie29-live \
  --command '{"op":"capture","filename":"LIE29-Wall-Actual.png"}'
```

The image MUST originate from `op=capture` in a live native compositor session;
a generated rendering is not valid laboratory evidence. Until that command runs,
the branch has *source only*, not a validated screenshot.

## Verified native evidence

GitHub Actions run `38250137472` executed native Godot 4.7.2 with Mesa
software Vulkan and finished successfully. The actual unmodified compositor
image is committed as `evidence/LIE29-Wall-Godot.png` and its SHA-256 plus
reproducible seed-change/restore checks are in `evidence/LIE29-validation.json`.
This is not a physical-GPU throughput benchmark or a cinematic-quality model.
At running-bond ends, half-brick termination is not yet implemented.
