# LIE 2.5: physical speed gain, failed near-camera visibility

The user reported stepped/deformed brickwork and black grain during the GPU
comparison on 2026-10-21. Both screenshots lack a visible backend label. The
restored report backend (`views`) does not identify the screenshot-time mode.

The phone now supplies actual paired Mali-G720 MC7 measurements. At 720,
regions / adjusted / simple camera appearance p50s are 28.46 / 16.96 / 7.30 ms;
p95s are 33.23 / 24.36 / 8.03 ms. Adjusted removes 40.4% of the median camera
interval. Simple is a deliberately inaccurate cost control, not an accepted
rendering mode. These intervals are not full-frame FPS. The adjusted median
already exceeds the 16.67 ms 60 Hz budget, before other frame work.

Moved-light p50s at 720 are 17.55 / 18.39 / 17.36 ms. All modes use the same
regions shadows; a new primary representation is not a faster shadow system.
The user-supplied rounded header is preserved separately in
`checkpoints/LIE25_MALI_CAPTURED_VIEWS.json`; the pasted raw JSON was truncated.
Main and diagnostic stage medians must not be added together.

## Reproduction of the reported pose

`diagnose_lie_direct_views_case.gd` instantiates the existing laboratory and
uses validated commands at yaw -72.90939846038818, elevation
2.0563994513617607, distance .6, neutral light azimuth -53.4 and power 1,
fill azimuth 55 and power .32, exposure 2. The diagnostic uses 720 internal
and output grids, and runs regions / adjusted / simple with shadows on/off.
The production modules are unchanged from APK runtime commit
`2836e6b941ae638f4788fe6c28755e7b8bfdc581`. Exact compiled bank and atlas bytes
were recovered from its verified CI APK. The GDExtension hardware counter
module is not needed for these native rendering/readback operations.

The six captures ran on Godot 4.7.2, actual native RenderingDevice Vulkan,
llvmpipe LLVM 17.0.6. They are **software reproductions of image defects**, not
additional Mali performance measurements. The severe stair/strip deformation
reappears in simple views. Adjusted also loses coverage at this pose.

| Native coverage at this exact pose | Regions | Adjusted | Simple |
|---|---:|---:|---:|
| Pixels with a valid surface | 138812 | 133717 | 109738 |
| Region hits missing in this mode | 0 | 6531 | 31493 |
| Missing hits inside a fully covered 5x5 region neighborhood | 0 | 2897 | 25539 |
| Coverage IoU against regions | 1 | .94319 | .75988 |
| Overlapping hits selecting a different brick/mortar instance | 0 | 20272 | 42482 |

Regions is a comparison baseline, not source ground truth. Missing pixels can
include border/visibility differences; the interior metric separately shows
that differences are not confined to the silhouette. World coordinates and
owners are finite. Shadow-toggle pairs have byte-identical world/owner data.
A .95 coverage gate used at other poses would fail for adjusted at this pose;
the previous passing cameras did not cover this case. Coverage alone also
misses wrong depths and wrong occluders.

Among valid adjusted hits, 35514 have output max(R,G,B)<.025 with shadows;
23649 of those rise above that threshold when only shadows are disabled.
For simple the counts are 44473 and 37432. Thus dark grain is not exclusively
missing geometry. This ablation does **not** establish that every dark point
is shadow acne, or distinguish legitimate occlusion from a primary/shadow
surface mismatch. Genuine dark source colors and normal/material aliasing
can also remain. Raising exposure or filling every empty texel would not
repair lost visibility and could cover real openings.

## Architectural interpretation and disposition

The cheap path samples one orthographic depth image and treats its visible
surface as the surface for a different perspective camera. It lacks sufficient
parallax correction and disoccluded information. The nearest angular capture
can change abruptly. This explains a reproducible deformation without invoking
a device-only driver fault. Adjusted performs fixed corrections and selects
among three captures, but still has no guarantee of a correct intersection
at depth discontinuities or newly exposed surfaces. Original high-resolution
materials do not restore missing visibility.

Both view paths remain experimental for this near-wall camera. The 7.30 ms
simple time cannot serve as the usable-quality FPS result. The next acceptance
case must include this exact pose, depth/owner correspondence, small camera
motions, and real image review. The benchmark needs a fixed, visible active
backend/resolution label and an unmistakable simple-control warning; its
current below-scroll status makes failures look intermittent and unattributed.

For architecture selection, retain the direct-access cost evidence while
requiring continuous, depth-consistent visibility over the allowed camera
range. A one-layer view approximation alone is insufficient here. A layered
or explicitly connected captured surface is a hypothesis to evaluate against
this failure, not a demonstrated fix or a promised speedup. Repeated depth
refinement, denoising and engine migration do not by themselves supply the
missing visibility information.

No production shader, application UI or APK is changed by this diagnostic
checkpoint. Visual defects remain open. Numerical evidence and file hashes
are in `checkpoints/LIE25_PHONE_POSE_DIAGNOSIS.json`.

Reproduce after restoring the verified 2.5 bank/packets into the project:

```sh
godot --path gpu_compute --rendering-driver vulkan --rendering-method mobile \
  --audio-driver Dummy --script res://diagnose_lie_direct_views_case.gd
python tools/lie_direct_views_diagnosis.py \
  --captures gpu_compute/diagnosis --output /tmp/lie25-diagnosis.json
```
