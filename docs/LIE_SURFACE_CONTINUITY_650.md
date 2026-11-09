# LIE 6.5: validated surface continuity candidate

Final executable source: `177523c25cc3eb5989939df8dc3b11c2285335d4`.
[Successful Android build and complete evidence](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42656719380).
[Review](https://github.com/heliossamuelhernandezreyes/Lie-Engine/pull/74).
Machine-readable acceptance: `checkpoints/LIE_V650_SURFACE_CONTINUITY.json`.
Historical investigations and negatives: `checkpoints/LIE650_WORK_IN_PROGRESS.md`.

## Result

Camera disk footprints no longer stop at a hard 64-pixel radius or disappear
solely because their center crosses the near/far plane. Exact disk conics and
a conservative clipped path retain visible support. Depth, deterministic
instance ownership and material accumulation run as distinct global passes;
opaque neighboring instances cannot blend merely within the depth tolerance.

Large footprints use a 64-lane cooperative queue in the existing jobs binding.
Original source bounds, support rectangles and instance cuts conservatively
bound its pixel work; final coverage predicates remain authoritative. In the
local before/after control this reduced close-view candidates by 72.2%, with
accepted counts unchanged and compared color/depth/shadow buffers byte-exact.
This is a work-count observation, not an Android speedup claim. Correct coverage
can cost more than the previous path which discarded visible fragments.

The projection remains 64 bytes. All 105 source-capture/metadata files match
the accepted 6.4 APK byte for byte; scene recipes, default LOD/resolution,
source-owned field and full shadow domain are retained. New queue arenas are
reported separately and reused at adequate capacity. Storage/device limits are
queried and checked before unsupported allocations.

## Controls

- **Superficie continua** defaults on; off selects the frozen 6.4 camera kernels.
  Both frozen kernel files match commit `94ac4f1ee225da96155f7e60433f9eaf11408f71`.
- **Inspeccionar ladrillo completo** selects one original 480,000-sample LOD-0
  brick. Returning through the scene selector restores its declared LOD.
  Over-budget requests are rejected before changing state/revision/geometry.
- **Probar superficie y copiar** retains all eight whole/close A/B/B/A blocks,
  then restores both controls and the actual compositor. Same source, LOD,
  lighting and resolution are used for each paired camera path.
- Copies omit repeated histories, keep every block, verify clipboard roundtrip
  and use declared dense columns for long sessions. Complete JSON export retains
  the raw histories. Oversized summaries request file export rather than claim
  a successful bounded copy.

Diagnostics run after production end timestamps and outside measured blocks.
Four separate GPU traversals read production projections/depth/winners/source
support; image/visibility buffers are declared read-only. Only statistics in
binding 20 are written and 32 bytes per active bank are read back. These are
separate predicate counts, not hardware instruction counters. All seven
production SPIR-V binaries remained byte-identical across this isolation.
Uint32 counter overflow is explicit.

## Acceptance

| Check | Final result |
| --- | --- |
| Python | 292 tests, one skip |
| Independent analytic Vulkan oracle | 29 cases, zero coverage/owner mismatches |
| Real-bank Godot Vulkan suites | 256 checks across seven suites |
| Frozen 6.4 float-buffer comparison | 10 cases; exact depth/alpha, max RGBA error 0 |
| Headless metrics/report suite | 12 checks, including all 60 session blocks |
| Source integrity | all 105 files identical to 6.4 |
| APK | ARM64, identity/assets/licenses/entry scene verified, signed and aligned |

The final CI uses official Godot 4.7.2 and Mesa llvmpipe/LLVM 21. Local oracle
controls also passed on SwiftShader and Mesa 26/LLVM 19. The complete compositor
and diagnostic equality are tested on attributed real capture banks, not only
analytic fixtures. Physical Poco/Mali validation remains pending; software
Vulkan timings do not imply phone FPS or photographic fidelity certification.
Entering an object does not create uncaptured interior geometry. Invisible
collision remains an independently selectable approximation.

APK: `LIE-Construccion-v6.5.0.apk`, 227,511,098 bytes.
SHA-256: `53146e01153ea8f9b022d57e3c824000b2d1462fc5cf038fe3990ad2e1d50db8`.
Package: `org.lieengine.construction.v650` (coexists with 6.4).
No physical-device performance target is certified by this release.
