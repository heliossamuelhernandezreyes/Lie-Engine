# Source continuity and shared 3D visibility — WALL10 / 0.7

The photographed bank remains byte-identical to WALL09:
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
This stage changes selection IDs and adds camera-independent short visibility
queries. It introduces no original mesh draws and retains the one invisible
wall collider. Accepted native/Android evidence is recorded below and in
`checkpoints/LIE_SOURCE_SURFACE_CHECKPOINT.json` and
`checkpoints/LIE_SOURCE_SURFACE_NATIVE.json`.

## Source selection

`tools/lie_asset_surface.py` partitions genuine 80-byte captured records by
geometric-normal hemisphere and balanced spatial strata. Four nearby genuine
members per stratum provide seeded choices. The wall adapter creates 96
distinct deterministic selections at each existing 4,000 / 1,300 / 240 budget.
Poses, tints, source positions, normals, RGB, radii and mortar records are not
edited. Work counts and reference-buffer sizes remain identical.

The compiler reports all four candidate variants and the first four actual
seeded instance selections against their original selections. The independent
measurement is nearest genuine 3D-source distance (p95/p99/max), normal
agreement and RGB means. This measures spatial representation; it does not by
itself establish photo fidelity or continuous coverage at every camera angle.

`test_lie_source_reference_gpu.gd` also renders one brick with the actual
reconstruction shader at three angles. Its reference uses all 220,000 genuine
captured source records at their original radii; both equal-budget candidates
use the existing 5.2 mm reconstruction footprint. It records missing/extra
pixels, world-depth MAE and linear-albedo MAE, and saves all nine images. This
is a dense captured reference, not an original mesh render or a photograph.

## Shared source geometry, separate instance scene

Each master has one BLAS over its captured tangent disks at original radii.
The generic compiler uses balanced spatial partitions, leaf lists of at most
eight source IDs, outward-rounded bounds and a depth-first escape index.
Node ABI: 32 bytes; low.xyz + escape uint bits, high.xyz + leaf-list uint bits.
Internal leaves use `0xffffffff`. Sphere bounds contain the tangent disk; a
bound hit alone never occludes light. Every leaf still solves the actual
ray/plane intersection and finite-disk test.

Instances supply an invertible affine inverse and a master root; a small TLAS
accelerates their bounds. Transformed ray directions remain unnormalized so
the ray parameter retains world-meter units through nonuniform scale. The
wall adapter includes the existing render-time XY expansion after the seeded
yaw, and the photographed mortar uses its own master with identity transform.
This adapter knows the wall layout; the common GLSL query does not.

The bank, BLAS nodes and leaf IDs are shared between cameras. Scene TLAS data
and writable source-visibility caches remain per consumer. The new registry
validates packet digests, references their lifetime and protects diagnostics
with a mutex. The loader validates identities, finite bounds, monotone escapes,
leaf/source bounds, affine rows and scene ranges before GPU allocation.

## Visibility and cache

The common `lie_source_visibility.glslinc` has no camera/depth-buffer input.
It tests all source occluders along the bounded light segment, including
hidden/back-facing/off-screen samples and other instances of the same master.
Only the receiver's own source ID in its own instance is skipped. Limits remain
2.5 cm reach, 0.3 mm normal bias and a smooth last-quarter fade. The existing
finite-patch field retains larger-scale visibility and all bounce budgets.

The raster pass marks genuine winning source projections. A separate GPU
stage queries each winning source patch/light once and caches visibility in
eight bytes per projected work slot. The upper bit retains winner activity
through light-only updates. Lights 0–6 use eight-bit normalized visibility;
light 7 uses seven bits. Quantization applies only to this extra attenuation.
The receiver anchor is the genuine captured source center, not an extrapolated
screen-pixel tangent position. Recovered pixels reuse a witnessed source's
visibility and never become new occluders.

The appearance pass consumes this cache in the existing direct/indirect split.
Indirect radiance is unchanged. Exposure runs output only; idle runs no new
visibility; light changes reuse geometry and winner activity. A source-selection
change invalidates geometry; camera/size changes rebuild it. BVH packets and
sample bank remain resident. No runtime CPU geometry/ray readback drives light.

The app exposes independent distributed-selection and 3D-shadow switches.
With both OFF the WALL09 source path is preserved. Contact steps control the
screen-space comparison mode only. The profiler reports `world_visibility`
separately and groups timings by actual source/world options and resolution.

The new immutable BLAS requests 5,943,064 GPU bytes, once per device and source
identity. Each consumer also requests a 13,184-byte scene packet and 6,000,000
bytes of writable visibility cache. The selection reference buffer retains its
3,088,388-byte budget. Equal source projection counts do not imply equal total
GPU time: 3D queries are additional work, measured as their own pass.

## Limits and acceptance

The disks approximate captured geometry. They are not watertight triangles,
an exact solid, native Godot depth/shadow participation, transmission or a
certified image-integrated radiance quadrature. Fine visibility is constant
within each selected reconstruction patch. Coarse irradiance visibility still
gates direct light. The current scene TLAS is compiled for static authored
instances; scene/geometry edits require recompilation and field acceptance.
The inherited photographic mortar remains metrically uncertified. Sampling
improvements do not convert it into measured 3D mortar.

Five common CPU tests cover source-ID determinism, outward bounds and complete
leaf membership, non-invertible transform rejection, camera-free visibility,
true openings, reversed light, rigid/nonuniform transforms and same-master
instancing. GPU fixtures execute the same common GLSL against exhaustive
float64 disk intersections. Full-wall acceptance includes OFF equivalence,
source/work/pose ownership, exact shadow alpha, cold/cache agreement, idle,
exposure, angled camera, resizing and shared producer lifetime.

Local staged import and seven source command checks pass; rig 247 and agent
25 checks pass. The first agent invocation in a fresh checkout reported an
unimported `.glsl` dependency despite printing 25 checks. It is not counted as
a clean success. After importing the project, the rerun passes without errors.

Two negative native runs are preserved:

- Run `38681073795`, code `2c7fd839`: all 68 visibility checks passed, but
  the dense-piece fixture placed instance 42 in slot 0 while support clipping
  still used owner 0. The nonempty-reference guard failed. Commit `823b1564`
  retains the original resident instance table and owner 42 for its one job.
  No production shader or tolerance changed. Artifact `11948096702`, ZIP SHA-256
  `f236ba29066cedf7559d23e4e6f025f5db8fa80d801a3da21c2deb85ad622dbf`.
- Run `38681532435`, code `823b1564`: all 15 dense-piece checks and the first
  13 full-wall checks passed. The two-camera fixture incorrectly attached two
  WorldEnvironments to one viewport, then assumed the second compositor had
  rendered. Access to the missing cache key raised a script error, leaving the
  process alive until the 25-minute job timeout. Commit `ef348f53` gives the
  second consumer its own rendered SubViewport/world, explicitly guards actual
  readback, and bounds each new native test to five minutes. Artifact
  `11949416217`, ZIP SHA-256
  `7bd4e4ce020459244ba85d548e0ec82da91a924705a2732de05a3f08a046f49f`.

The dense captured reference confirms fewer missing/extra pixels, but the
distributed subsets do not improve every error measure. At the same enlarged
rendering footprint, source-albedo MAE is slightly higher at the three tested
angles; depth MAE is slightly higher at 0 and 60 degrees. Grain, surface
extrapolation and oblique silhouette errors remain visible. This stage is a
measured coverage improvement, not a claim of photographic equivalence.

## Accepted native run and APK

Run [38691565933](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38691565933)
at runtime commit `ef348f5380d16b7fcf44549a3032000b00b5a998` passes:
68 source-visibility checks, 15 dense-piece checks, 18 full-wall checks and
seven strict command checks. Previous 374 common-field, 404 surface-field,
88 contact, 80 stencil, 27 registry and WALL07/08/09 checks also pass.
The stage imports cleanly, and native logs contain no engine errors or leaks.

Both new switches OFF reproduce WALL09 exactly (RGB max error 0, IoU 1).
World visibility changes shading with alpha error 0. Cached and cold light
images agree within `7.699709385633469e-7`, with IoU 1. Actual independent
viewports share one source bank and one BLAS upload; deleting the second
viewport preserves the first consumer's lease. The 1440 angled render also
passes without reuploading the source bank.

The first four measured seeded selections reduce mean p95 source distance
by 26.84%, 25.15% and 22.74% at the existing 4,000 / 1,300 / 240 budgets.
For the one-brick dense comparison, with the same rendering footprint:

| Camera angle | Missing pixels, legacy → selected | Extra pixels, legacy → selected | Selected depth MAE | Selected linear-albedo MAE |
| --- | --- | --- | --- | --- |
| 0° | 19 → 1 | 583 → 534 | 1.059 mm | 0.03029 |
| 35° | 17 → 0 | 496 → 419 | 2.011 mm | 0.03136 |
| 60° | 12 → 0 | 501 → 423 | 2.820 mm | 0.03121 |

These are 256×256 actual shader images, without hole recovery, against dense
captured disks rather than an original mesh render. They are not measurements
of the user's screenshot or a guarantee for every source asset.

At 1080 internal resolution, the appearance requests 242,631,644 bytes and
transport requests 1,544,056 bytes. The new visibility pass reports p50 398.27
ms / p95 412.07 ms over only five changed-image solves on **software Vulkan
llvmpipe**, not mobile hardware. This is substantial extra measured work in
that environment; physical GPU speed cannot be inferred from it. Idle and
exposure reuse the existing cache. The APK includes independent switches and
a visibility timer so the Poco can compare actual cost and quality.

Signed ARM64 APK: `LIE-Superficie-0.7.0.apk`, 57,738,754 bytes, SHA-256
`b79dcd4912d881cbf2e8c0af0ef6ebc6a663027285e61898118d348184cd1cd6`.
Package `org.lieengine.wallruntime.v070`, version code 7; minimum SDK 24,
target 36. V2/V3 signatures, 16 KiB alignment, source-bank and all new packet
identities are verified. It is offline and installs beside 0.6 for comparison.
Godot's core remains the official 4.7.2 build; this implementation runs through
LIE's existing RenderingDevice/compositor path.

Primary research: [Surface Splatting (MERL, 2001)](https://www.merl.com/publications/TR2001-20)
describes source splat filtering and irregular samples;
[PBRT's BVH chapter](https://www.pbr-book.org/4ed/Primitives_and_Intersection_Acceleration/Bounding_Volume_Hierarchies)
describes primitive hierarchies and object-space ray acceleration. These inform
the design; they do not establish this implementation's visual quality or
performance. Physical Poco measurements remain required. Software Vulkan
timings must not be presented as phone FPS or sustained thermal performance.
