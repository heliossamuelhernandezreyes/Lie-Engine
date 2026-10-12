# LIE33 — True 1080-square tiled GPU dispatch

LIE22/LIE31 ran a single compute-dispatch dimension with a fixed local size
of 64. At native 1080×1080 output and double-size internal 2160×2160,
some stages required 72,900 X workgroups, exceeding Vulkan's typical 65,535
groups-per-dimension limit. The earlier LIE31 1080² image was empty.

LIE33 fixes this by splitting each stage across two workgroup dimensions.
X is capped at 65,535; Y continues the linear invocation index.
GLSL uses `gl_GlobalInvocationID.x +
gl_WorkGroupID.y * gl_NumWorkGroups.x * gl_WorkGroupSize.x`.

Validation:

- Source bank unchanged from LIE31: physically displaced CC0 Poly Haven
  4K brick-map-derived LIE samples; no new 3D brick scan.
- Godot 4.7.2 / Mesa software Vulkan native compositor: 1080×1080 pixels,
  **not** a 1920×1080 aspect-ratio frame and **not** an enlarged 512 image.
- 126 logical bricks plus mortar, 127 instances and 437,306 sample invocations.
- Hero brick and full wall passed nonempty original compositor readback.
- Binary SHA report: `evidence/LIE33-native1080-report.json`.
- Native wall: `evidence/LIE33-Wall-Native-1080-Square.png`.
- Native brick: `evidence/LIE33-Brick-Native-1080-Square.png`.
- GPU workflow:
  https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38275590357
- Math regression: `tests/test_lie33_tiled_dispatch.py`, covering every
  pixel once at 1080² / 2160² and boundaries near the 65,535-group limit.

Limitations: no wide 1920×1080 render target or rectangular memory layout yet;
no hardware FPS result; source brick still derived from 4K photo height maps.
Source scanned 3D geometry research progresses separately in LIE34.
