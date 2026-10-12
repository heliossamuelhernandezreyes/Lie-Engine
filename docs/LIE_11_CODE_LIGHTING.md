# LIE-11: grayscale sprites, material codes and conservative light bounces

## User's mechanism and scope

Visible appearance belongs to grayscale sprites. XYZ nodes hold spatial data and
material codes; a light injects illumination and color into nodes within a radius.
An absorption code removes a fraction of received energy. The remaining colored
power is a secondary diffuse source, with successive weaker generations.

This change implements that mechanism as a separate runnable laboratory within
Lie's existing Godot RenderingDevice project. It does not replace earlier labs
or draw their source GLBs. The fixture uses 64 actual Sprite3D nodes forming an
open room; an optional blocker is also shown with a grayscale sprite. Sprite3D's
internal textured quads are ordinary rendering primitives, not visible source
asset meshes. The point-light and bounce computation runs in Vulkan before the
sprites are drawn, and the sprites consume an HDR node-code texture directly.

## Physics and approximations

All computations use **linear RGB relative power**, not sRGB arithmetic or
calibrated spectral watts. For opaque material code `a` in 0..1000 and a linear
RGB filter `c` in [0,1], the patch-average reflectance is

`rho = gray_mean * (1 - a / 1000) * c`.

The grayscale image is neutral reflectance detail with no baked directional
shadows. The material filter expresses which RGB components the surface returns;
it is multiplied into the received light rather than added as new energy. This
v1 has one material and one world-space normal per planar sprite patch. Different
parts of a multicolored or curved captured asset would need smaller patches or
per-pixel material IDs and normals; those are not silently approximated as complete.

An isotropic point source with power `P` contributes a fraction to patch i:

`w_li = V_li * A_i * max(dot(n_i, direction_to_light), 0) * window(d/r) / (4*pi*max(d^2, 0.05^2))`

where `window(x) = max(0, 1 - x^4)^2`. The inverse square and cosine follow
radiometry; the 5 cm softening and finite radius window are explicitly artistic
approximations. Coarse center quadrature can overestimate the covered solid angle,
so fractions from each source are divided by `max(1, sum_i w_li)`. Unassigned or
occluded power is discarded rather than redistributed to every neighbor.

For source patch i and receiver j, the center approximation is

`F_ij = V_ij * A_j * cos_i * cos_j / (pi * d_ij^2)`.

The cache builds symmetric pair coupling, then applies **one global correction**
if any row sums above one. This preserves `A_i F_ij = A_j F_ji` and makes every
row sum at most one. It is a conservative finite-patch approximation, not the
exact area-to-area form-factor integral. A row's missing mass escapes or is
blocked. Visibility uses authored opaque AABBs and open-segment slab intersection;
this provides testable blocking without rendering source geometry. The proxy
contract must match real opaque obstacles in an actual game.

The recurrence tracks only the latest generation:

`out_i^(k) = rho_i * received_i^(k)`

`received_j^(k+1) = sum_i F_ij * out_i^(k)`.

The running total is used for display, **never as new source power**, preventing
double counting. Each color's outgoing power cannot exceed its incoming power,
and aggregate next-generation input cannot exceed previous-generation output.
The default is two secondary generations, with a hard limit of eight. The shader
has a nonnegative cutoff parameter (zero in validation); discarded contributions
are lost power. Diffuse outgoing radiance for the sprite display is

`L_pixel = gray_pixel * (1-a/1000) * c * E_node / pi`,

with `E_node = accumulated_received_power / patch_area`. A fixed `L/(1+L)` display
mapping follows; diagnostics retain unclipped linear power.

## Architecture and integration

- `tools/lie_light_transport.py`: independent Python float64 reference, physical
  invariants, room generator and an independently solved linear system for the
  infinite-bounce limit of the **same coarse graph**.
- `lie11_model.gd`: schema/material validation and cached reciprocal transfer
  factors. The O(N^2) cache is constructed on CPU when surface/blocker data changes.
- `lie11_light_effect.gd` + compute shader: persistent GPU input buffers, primary
  weights and source caps, direct injection, ping-pong bounce generations, and
  resolve to an RGBA32F node texture. Runtime work is O(N*lights + bounces*N^2).
- `lie11_gray_sprite.gdshader`: grayscale/detail + material metadata + node code.
  It samples the GPU texture with no runtime GPU-to-CPU readback.
- `lie11_lab.gd`: XYZ, perspective, camera orbit and changing light/material codes.
  Moving a light only updates the persistent light buffer; static factors are reused.

The RD texture wrapper is published once on the main thread before material
creation. Diagnostic readbacks are explicit test actions. The effect does not
overwrite the framebuffer after transparencies; ordinary opaque sprite depth
testing remains active. This is not yet the combined Lie/native depth contract
needed for rain in the older image compositor.

Integration with captured complex assets must supply unlit grayscale reflectance,
per-surface material codes and a surface/visibility proxy consistent with their
stored depth. This prototype establishes the lighting module and its material
consumer; **LIE-10's Blender reprojection shader remains on its earlier directional
lighting model**. Dense global graphs are a research baseline; spatial clustering,
sparse edges and update budgets are still needed before large scenes.

## Verification and reproducibility

```
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 tools/lie_light_transport.py
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --editor --import --quit
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --script res://test_lie11_lighting.gd
```

The dedicated workflow generates the independent reference, compiles the real
Vulkan shader, reads back linear node powers for six scenarios and compares them
to float64. It also compares the actual rendered GPU-code frame to the identical
sprites shaded with independent reference codes, and verifies perspective scaling
and an orbit camera. The fixture and all six scenarios are deterministic.

Tests cover inverse-square behavior away from the explicit source cutoff,
orientation, blocked direct light, finite radius, color filtering, stronger
absorption, zero light, complete absorption, area reciprocity and per-channel
energy conservation. Iterative results converge to the independently solved
linear system. Local reference results put the default two-bounce truncation
about **4.71% below the infinite-bounce solution in relative total-power L1**
for this fixture; this is not a physical-scene accuracy estimate.

Frames and `lie11-diagnostic.json` report the actual device name, six GPU-reference
errors, owned GPU allocations and 120-frame process-spacing p50/p95/p99 for zero
and two secondary generations. Owned allocations exclude engine resources,
textures for the sprites, driver overhead and total VRAM. GitHub CI uses software
Vulkan; its timings are not isolated hardware GPU times, Android FPS or evidence
of a speedup over conventional rendering. CI results must be checked before
claiming the implementation runs successfully.

## Remaining limits

Opaque diffuse materials only. No mirror images, Fresnel/specular highlights,
water transmission/refraction, soft penumbrae, per-pixel shadowing or volumetric
scattering. Authored AABBs are a coarse blocker representation. Patch lighting is
constant inside each sprite; its grayscale detail remains spatially varying.
The physics and light/color codes are compatible with sprites, but the choice of
representation does not remove the need for spatial visibility or material data.

## Primary sources

- Pharr, Jakob and Humphreys, *Physically Based Rendering*, fourth edition:
  [point sources and inverse square](https://www.pbr-book.org/4ed/Light_Sources/Point_Lights),
  [diffuse reflectance](https://www.pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection),
  [surface scattering and energy conservation](https://pbr-book.org/4ed/Radiometry,_Spectra,_and_Color/Surface_Reflection).
- Laine et al., *Incremental Instant Radiosity for Real-Time Indirect Illumination*,
  Eurographics 2007: [author-hosted paper](https://users.aalto.fi/~laines9/publications/laine2007egsr_paper.pdf).
  Its virtual secondary-light principle supports the approach; Lie's particular
  coarse node graph, normalization and grayscale data contract are separate choices.
