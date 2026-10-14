# LIE-35: directional optical codes, experimental isolated GPU slice

**Status:** opt-in mathematical and Vulkan experiment. Not the default LIE-11
renderer, not merged into WALL04, and not included in any Android APK.

## Why this exists

LIE-11/19/35-wall transport distributes largely diffuse node power. LIE-13
already models Snell, Fresnel and RGB extinction for *thin sheets*, and the
new CSR and lighting cache preserve diffuse transport performance. However,
captured normals and roughness have not yet become a directional *secondary*
light emission law for opaque samples and metal, and refracted transmission in
LIE-13 is a straight-segment illumination filter.

This branch tests the user's proposed **capture attributes -> angular material
code -> finite-radius RGB spatial propagation** without replacing established
rendering or fabricating pixel coverage.

## Actual implementation

- [Reference](../tools/lie35_directional_reference.py): independently
  evaluated float64 light redistribution and energy budgets.
- [GPU](../gpu_compute/shaders/lie35_directional.glsl): real Vulkan compute
  with three phases: angular link weights, per-emitter normalization and
  receiver gather. No floating-point atomics, no original mesh rendering.
- [GPU acceptance](../gpu_compute/test_lie35_directional.gd): compares
  channels against Python float64 for brick, colored metal, absorbing clay,
  glass, range cutoff and mixed emitters.
- [Python tests](../tests/test_lie35_directional.py): physical sanity and
  passivity checks, plus invalid input rejection and cutoff continuity.
- [CI](../.github/workflows/lie35-directional-optics.yml): GitHub Actions
  Python+Mesa Vulkan. Its result, not the presence of the workflow, determines
  validation status.

Each emitter stores six vec4s (96 bytes): XYZ and effective radius, geometric
normal and roughness, incident light travel direction and metalness, RGB
albedo and transmission fraction, RGB extinction sigma (m^-1) and thickness
(m), and RGB incident power plus IOR. Each receiver stores XYZ/area and
normal/visibility. These properties are **authored test material codes**, not
automatic data already captured from WALL04 bricks.

The diffuse lobe uses max(n·out,0), glossy reflection a normalized-by-discrete-
links roughness-dependent *Phong-like angular kernel*, and transmitted
radiance a roughness-dependent lobe centered on the Snell direction. The
Fresnel factor uses Schlick with conductor RGB F0 approximated by albedo,
dielectric scalar F0=((ior-1)/(ior+1))². Beer-Lambert attenuation uses
exp(-sigma * thickness / cos_transmission).

This is **not a GGX microfacet BSDF** or an exact dielectric path tracer.
Metal albedo -> F0 and roughness -> exponent are approximations; the actual
captured material maps and tangent normal fields need a documented ingestion
contract in later work. Reflection lobes are not guaranteed to be physically
normalized over continuous solid angle; they are normalized over available
discrete receiver connections to prevent gaining energy.

### Passive source bound

For each source and RGB channel, calculate nonnegative diffuse D, reflection
R, and transmission T coefficients, each collectively bounded by unity.
For every outgoing link j, compute geometric/visibility/radius-weighted
nonnegative lobe weights w[j,l]. Normalize per emitter and lobe with
c[l] = max(1, sum_j(w[j,l])). Then

    received[j,k] += P[source,k] *
        (D[k]*w[j,d]/c[d] + R[k]*w[j,r]/c[r] + T[k]*w[j,t]/c[t])

Thus sum(received[j,k]) <= sum(P[source,k]) for passive nodes and finite
input, without renormalizing discarded energy upward. The same construction
holds across generations **if** future integration feeds each new generation
only the previous outgoing frontier (as LIE11 does).

The finite radius is explicitly a **quality cutoff**, with a smooth
(1-(d/R)^4)^2 edge and inverse-square geometric spreading. In the production
engine, the separately tested LIE runtime energy-radius rule should supply R;
the new GPU kernel consumes an already chosen radius. A node outside the
visible camera may still affect receivers and must not be culled merely for
being offscreen.

### Current boundaries

- O(N_sources*N_receivers) buffers and work, max 128 each. This is for
  correctness, **not** suitable for all WALL04 nodes or thousands of actors.
  The next GPU integration should adapt the current reciprocal CSR graphs,
  angular source-receiver adjacency, conservative culling, LOD clustering
  and lights/material caching.
- A single incident direction per source, with no multiple-light angular
  mixture or iteration of its direction after each bounce. Passivity is
  demonstrated for **one transport step**, not complete lighting quality.
- The glass interface assumes entry from air; no total internal reflection
  or interior media. A Snell result is used to steer the emitted lobe,
  not a physically exact caustic. No volumetric multi-scattering.
- Receiver area, point distance and directional lobe are quadrature
  approximations; a consistent radiometric calibration and a Cycles/PBRT
  comparison are still needed.
- The existing 96-brick WALL04 capture, 872 LIE11 nodes, shadow AABBs,
  Android APK and baseline 36-60 FPS observations are **unchanged**.
  No improvement in frame rate or photorealism is claimed here.

## Reproduce

    python -m unittest discover -s tests -p 'test_lie35_directional.py' -v
    python tools/lie35_directional_reference.py
    godot --headless --path gpu_compute --editor --import --quit
    xvfb-run -a godot --path gpu_compute --rendering-driver vulkan \
      --rendering-method forward_plus --script res://test_lie35_directional.gd

LIE-35 is useful if it establishes three independent facts: response changes
with material, outgoing RGB is passive by construction, and the GPU reproduces
the independently computed answer. Only after those gates pass should it
be connected to LIE-11's actual scene-wide transport or the WALL04 renderer.
