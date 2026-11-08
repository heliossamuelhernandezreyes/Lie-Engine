# Exact LIE compute replay

This is an isolated control experiment, not a replacement game engine. It
replays the original Godot-produced SPIR-V and the exact bound buffer bytes
for clear, projection/depth and material accumulation. It omits shadows, the
light field, shading, presentation, physics, audio, UI and platform lifecycle.

The accepted runtime is `3aacb5e58034042f9a8e9c19a7bcf4e8b7823054` (6.3.0).
The audit does not change its capture banks, LOD, reconstruction dimensions or
production kernels. Candidate shader changes are generated separately and
remain unadopted. Godot and native output depth, winner ownership and material
accumulation must match every byte in the baseline experiment.

## Reproduce

Run `.github/workflows/lie-architecture-audit.yml`, or use its exact commands
locally. The workflow restores the SHA-pinned 6.3.0 APK, verifies its 90 asset
files, compiles Godot 4.7.2 fixtures on Vulkan, exports all shader inputs, and
executes the native control and two exploratory shader variants.

For an exported fixture on a Linux system with Vulkan development headers:

```sh
g++ -O2 -std=c++17 native/architecture_audit/replay.cpp -lvulkan -o lie-replay
./lie-replay /absolute/path/to/architecture-fixtures/whole
./lie-replay /absolute/path/to/architecture-fixtures/close
python3 tools/lie_architecture_audit.py --compare /absolute/path/to/audit-stage --output architecture-comparison.json
```

The fixture includes exact SPIR-V, bank inputs, parameters, layout and reference
hashes. Native output buffers are diagnostic files and are deliberately excluded
from CI artifacts. The smaller input fixtures retain source attribution. Do not
copy the large capture banks into Git.

The original fixture shaders have SPIR-V 1.4 headers (`0x00010400`). Executing
these binaries unchanged requires Vulkan 1.2 or Vulkan 1.1 with the
`VK_KHR_spirv_1_4` extension and its dependencies enabled. A different compile
target or backend needs independent validation.

The harness requests Vulkan 1.2 for this experiment, uses host-visible coherent
storage for straightforward inspection, performs one warm-up plus five samples,
and alternates bank order at a fixed camera. Those choices are not the proposed
minimum device tier or memory placement for a production mobile renderer.
Each timestamp interval is converted with the device timestamp period.
Projection and accumulation intervals are paired within a frame before taking
their median. CPU recording, submission/wait and GPU intervals have different
scopes; do not add their percentiles or turn software Vulkan results into phone
FPS. A speed difference from five samples is not a sustained-performance claim.

## Static Arm compiler analysis

```sh
python3 tools/lie_mali_static_audit.py --compiler /path/to/malioc --spirv /path/to/original-spirv --output /path/to/reports
```

The compiler is an external Arm product; its binary is not distributed here.
The audit records compiler version/hash, driver model, shader hash, registers,
estimated occupancy, spills and modelled pipeline cost. Successful compilation
does not validate device descriptor limits, driver correctness, thermals,
actual memory contention or Android performance.
