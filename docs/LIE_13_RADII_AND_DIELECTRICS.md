# LIE-13 — finite secondary-light radii and dielectric sprites

LIE-13 extends the LIE-12 captured grayscale/material consumer. Opaque captures
still use neutral sprites and invisible spatial proxies; visible source meshes
are never loaded. A second camera consumer interprets reusable optical sprites
as glass, water and curved rain drops in real XYZ, using metre dimensions.

## Secondary lights

Optional model `secondary_radii`:

```json
{"radius_max":4.0,"radius_decay":0.82,"power_reference":0.015}
```

Each node emits only its reflected frontier, not accumulated illumination.
Let `P` be outgoing RGB power, `rho` the RGB material reflectance, `Rp` the
largest contributing parent radius and `s` the material `radius_scale` (0..1):

```
R = s * min(Rp * radius_decay * sqrt(max(rho)),
            radius_max * sqrt(max(P) / power_reference), radius_max)
```

A direct-light frontier takes `Rp` from contributing primary light codes.
Subsequent frontiers take it from secondary emitters with nonzero contribution.
For each directed pair multiply the existing conservative form factor by:

```
window(d/R) = max(0, 1 - (d/R)^4)^2
```

Zero power has zero radius. High absorption reduces power and reach. Radius
falls along paths and the maximum falls between generations. Different paths
can illuminate a previously dim node: per-node brightness need not decrease.
The window never renormalizes removed power into other receivers. A material
can additionally reduce reach via `radius_scale`.

This radius is an explicit finite influence/quality policy, **not a physical
boundary where photons stop**. `power_reference` is relative linear RGB power,
not a watt calibration. Distance/form factors, absorption and the energy budget
remain separate. Omitting the policy preserves the LIE-11/12 transport.
Nonlinear power-dependent radii cannot use the old fixed-matrix infinite-bounce
oracle; tests instead compare each truncated generation and its energy bounds.

## Glass and liquid code

A thin sheet has `center`, orthonormal `right`/`up`, positive `half_width` and
`half_height`, `ior`, metre `thickness`, and nonnegative RGB `sigma` in inverse
metres. The visual sprite adds `kind` (0 glass, 1 water, 2 drop), `wave` and
`frequency`. One neutral normal/coverage atlas is reused for all instances;
there is no baked light or colored artwork. Drop coverage also codes relative
thickness. Water uses the analytic derivatives of two prescribed waves as its
animated normal field.

For an air-to-material interface we evaluate unpolarized dielectric Fresnel
and Snell, rather than treating transparency as a constant alpha. For slab
path length `thickness/cos(theta_t)`:

```
a = exp(-sigma * thickness / cos(theta_t))
T = (1-F)^2 * a
R = F + (1-F)^2 * a^2 * F
```

`R+T <= 1` componentwise. The second term in `R` is the first internal return.
Later internal returns are deliberately left untraced, not redistributed or
claimed as physical absorption. A perfectly index-matched, unabsorbing sprite
is an exact visual identity. Thicker colored material transmits less light;
grazing angles reflect more. CPU tests also cover total internal reflection
for the interface helper, though this visual slab consumer assumes air outside
both faces and is not a camera-inside-volume solver.

## Shared depth and composition

Compositor order: GPU light codes, captured opaque surfaces, optical sprites.
The optical consumer merges native opaque reverse-Z with the LIE GPU depth in
camera-linear Z, snapshots already composed color, then peels the four nearest
sprite intersections at each optical pixel from far to near. Sprite submission
order is irrelevant for distinct depths. Each pass reads one image and writes
another; no refractive sampling reads a framebuffer concurrently being changed.

Snell supplies a thin-slab lateral displacement, projected into screen space.
A displaced sample with depth closer than the current sheet is rejected and
falls back to the undisplaced color. This avoids foreground leakage. Reflections
use an explicit external environment gradient plus finite-angular highlights
from the same dynamic primary RGB/radius codes. The scene is not screen-ray
traced for reflected/off-screen objects. Coefficients remain linear until Godot
maps the final viewport; the LIE-12 opaque consumer retains its existing display
mapping, so this is not a newly calibrated radiometric HDR pipeline.

Limits: 64 optical sprite instances, four nearest layers per pixel, 256-square
optical images, mono perspective camera. Extra deeper layers are omitted by the
explicit layer budget. Source meshes remain invisible. Native blended sprites
outside this consumer still need a future unified transparent registration;
there is no writeback of LIE depth to Godot's native depth texture.

## Transmission of illumination

`optical_sheets` on the light model (maximum 16) filter both primary injection
and secondary patch-pair transport with the same RGB `T` above. Finite rectangle
intersection and direction-dependent path length occur on GPU. Opaque proxy
visibility remains in effect. This makes a sheet produce colored transmitted
shadows without acting as an opaque blocker. These are straight-segment filtered
connections: no refractive light-path bending, caustics, or new specular diffuse
sources are asserted. Rain drop instances are camera sprites and are deliberately
not each inserted into the diffuse transport graph.

Visual and transport sheets use the same schema. The laboratory registers glass
and water in both consumers by default, so changing material/thickness also changes
transmitted illumination. Optical acceptance can temporarily isolate the camera
consumer; a final coupled GPU/oracle case checks the shared registration. An
arbitrary native Sprite3D does not automatically become a transport sheet. T
toggles a documented transport-only sheet fixture.
The opaque Blender exporter still accepts constant opaque source materials;
transparent GLB capture/automatic volume extraction is a separate future task.

## Run and verify

Generate the coded capture exactly as in LIE-12, then:

```sh
python3 tools/lie13_reference.py gpu_compute/captures/coded_shard
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus res://lie13_lab.tscn
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --script res://test_lie13_optics.gd
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Arrows orbit; WASD moves the primary light. B toggles direct/bounces, X changes
red absorption, C changes source color, O switches source off, R switches short
secondary reach, T switches a colored transmission sheet. 1 clears optics,
2 glass, 3 water, 4 rain, 5 combined. Space pauses waves/drop motion. Default
project startup remains the previous lab; launch the LIE-13 scene explicitly.

The LIE-13 workflow generates actual Blender captures, CPU references, imports
all shaders into Godot/Vulkan, checks GPU irradiance and secondary radii against
float64, then checks actual optical pixels, thickness, wave animation, ordered
layers, native/captured depth and perspective size. Evidence is real viewport
PNG plus machine-readable diagnostics. LIE-11 and LIE-12 regressions also run.
Software Vulkan is functional evidence, not a claim of mobile or hardware FPS.

## Primary research

- [PBRT 4, dielectric BSDF](https://pbr-book.org/4ed/Reflection_Models/Dielectric_BSDF): Fresnel reflection/transmission and Snell directions.
- [PBRT 4, transmittance](https://pbr-book.org/4ed/Volume_Scattering/Transmittance): exponential attenuation along a path.
- [Godot 4.7 compositor](https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html): rendering stages and compute integration.
- [Godot RenderSceneData](https://docs.godotengine.org/en/4.7/classes/class_renderscenedata.html): actual camera transform/projection for shared depth.
