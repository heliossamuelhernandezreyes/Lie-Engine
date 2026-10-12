# R1 · modular robot masterkit

A complete industrial humanoid is assembled from three armor masters, a
cylindrical joint, a piston/shaft and a corrugated cable. The native LIE
compositor reconstructs captured surfaces; original source meshes are not
drawn by the runtime. The kit also includes original editable source geometry.

Branch `experiment/lie-robot-modular` is based on LIE-28 commit
`27a87c4f39c2163ac773db8d30208f091ec4136c`. Its PR targets
`experiment/lie28-building-masters`; main is not changed by this checkpoint.
The R1 namespace avoids collisions with concurrent numbered experiments.

## Masters and materials

| Master | Nominal authoring size, metres | Use |
|---|---|---|
| `plate_flat` | 0.22 × 0.34 × 0.046 | Beveled armor, screws, vents and indicators |
| `plate_shell` | 0.23 × 0.34 × 0.12 | Curved sheet with inner face and thickness |
| `plate_bracket` | 0.16 × 0.18 × 0.10 | Angled support and weathered steel |
| `joint` | diameter 0.164, length 0.15 | Grooved cylindrical joints and bolt caps |
| `shaft` | diameter up to 0.052, length 0.5 | Frames, telescoping pistons and fingers |
| `cable` | diameter up to 0.024, length 0.5 | Corrugated rubber with grommet ends |
| `ground` | 3 × 0.03 × 3, top at Y=0 | Separate studio support plane |

Actual bounds are in `catalog.json`. Coordinates are metres, Y up, with the
cylinder/cable longitudinal direction along Y. GLBs preserve these axes
(`export_yup=False`); do not apply a second Blender-to-glTF axis conversion.
Armor UV repeat scale is authored at 0.65 m, not a claim about the photographed
source's measured size. All geometry is original and reproducible.

Photographed surfaces are Rob Tuytel's CC0
[blue_metal_plate](https://polyhaven.com/a/blue_metal_plate) and
[metal_plate_02](https://polyhaven.com/a/metal_plate_02) from Poly Haven.
Eight **4096 × 4096** maps were acquired: diffuse, roughness, OpenGL normal
and metallic (the blue plate uses ARM's blue channel). Provider checksums,
local SHA-256, URLs and attribution are retained in `provenance.json`.
Machined steel, rubber, amber coating, cyan indicators and floor use original
procedural parameters. No paid/vault asset is used.

## Capture and rendering

`tools/lie_robot_prepare_blender.py` creates the original masters, packed
Blender asset library, GLBs, source-triangle/UV oracle and neutral captures.
It ray-casts 36 azimuth/elevation views per master at resolution 160, or 320
for the thin cable. Fine/coarse levels share one bank: **382,541 samples /
36,723,936 bytes**, below the 64 MiB limit. Each sample is six `vec4`s / 96 bytes:

| Field | Meaning |
|---|---|
| `position_radius` | Source-local surface position and reconstruction support |
| `geometric_normal_unused` | Geometry for coverage, depth and shadow bias |
| `zone_cell_roughness_metallic` | Material ownership, roughness and metallic |
| `linear_albedo_emission` | Neutral linear base color and emission |
| `face_support_bounds` | Per-face tangent-plane support bounds |
| `shading_normal_unused` | Independent captured normal-map shading normal |

The bank has no photographed baked illumination. Point-light GGX uses
metallic F0/diffuse behavior and captured roughness. An analytic studio
environment adds view-dependent metal reflections: sky/floor gradient and
three light lobes. This is an approximation, not HDRI, screen-space or
scene-ray-traced reflection. `unlit` exposes neutral base color for inspection.

One immutable resident bank supports at most 128 instances / 750,000 sample
invocations per evaluation. The saved body has **80 instances including
ground, six cables and 535,361 invocations**. Robot output is 768 × 768 with
a 1536 × 1536 reconstruction target. Other laboratories keep their previous
output defaults. Cable and ground stay at fine LOD; other pieces can use coarse.

## Articulation and cables

`lie_robot_assembly.gd` reuses the existing **`lie26_rig.gd` FK/IK evaluator**,
15 bones, semantic joint limits and foot targets. There is no second runtime
rig solver. Plates attach rigidly to bones; shafts join anchors, elbow pistons
telescope and three two-segment fingers respond to `grip`. Modes are manual
pose, reach and walking in place. Foot positioning uses IK.

Six rubber cables connect elbow, knee and spine anchors. A quadratic guide
solves for calibrated length, distributes 16 knots by arc length and parallel
transports cross-section frames. The GPU bends captured samples with Hermite
interpolation and transforms both normal types with the inverse Jacobian.
Radius is preserved; snapshots report length and clamping. This is kinematic
routing without cable elasticity, collision or tension physics. Extreme poses
can clamp; tested poses and walk targets remain reachable.

## Desktop and agents

Open `gpu_compute/lie_robot_lab.tscn`, use the editor dock's robot button, or:

```sh
python tools/lie_agent_launch.py --godot /path/to/godot \
  --lab robot --directory /absolute/path/new-robot-session
python tools/lie_workshop_client.py --directory /absolute/path/new-robot-session \
  --command '{"op":"set_pose","values":{"right_elbow":110,"right_wrist":-20}}'
```

Native widgets and agents share validated `command()` mutations. All fields,
ranges, pose limits and masters are discoverable. Controls cover camera,
light, coating color, grip, pose, cables, IK, floor, shadows, material view,
focus, time/playback and save/load. Invalid edits are atomic; existing revision,
session and path protections remain. The bridge publishes complete PNGs.

## Restore and reproduce

Obtain `R1-Robot-Maestros.zip` from `checkpoints/LIE_ROBOT_CHECKPOINT.json`.
Verify its exact size/SHA-256, then extract `assets/robot_modular` and
`captures/robot_modular` into `gpu_compute`. It contains original maps/masters,
assembled GLB, editable Blender source, saved state, reports, native PNGs and
walk frames. Code stays in Git; the package does not duplicate the checkout.

With Blender 4.3.2 and Godot 4.7.2:

```sh
blender --background --python tools/lie_robot_prepare_blender.py -- \
  --materials /absolute/path/source-materials
python tools/lie_robot_verify_captures.py --materials /absolute/path/source-materials
godot --headless --path gpu_compute --editor --import --quit
godot --headless --path gpu_compute --script res://test_robot_rig.gd
godot --path gpu_compute --script res://test_robot_gpu.gd --audio-driver Dummy
```

GPU tests need a working display and Vulkan device. For an already launched
disposable robot session with its bank restored:

```sh
python tools/lie_robot_agent_smoke.py --directory /absolute/path/new-robot-session
blender --background --python tools/lie_robot_export_blender.py -- \
  --session /absolute/path/new-robot-session
```

The exporter consumes native assembly packets. It creates a rest GLB and an
editable Blender model: frame 0 is rest; frames 1–17 bake 16 native walk
phases. This is original authoring geometry, not the runtime's rendering.

In workspaces that synchronize files during tool calls, keep live inbox/outbox
files in a private temporary directory outside that synchronized workspace.
Run launcher and client together, close the disposable session, then stage
completed evidence. A scratch-backed smoke run timed out after files were
replaced during synchronization; the isolated run passed. Never blindly retry
a timed-out command that may still execute.

## Verification and practical limits

- Python: 72 tests, one skipped; existing agent CPU: 20; LIE-27 regions: 888.
- Rig/cables: 3,734 checks; maximum cable-length error 0.1592 mm and foot IK
  residual below 0.00007 mm.
- Capture oracle: 840 source points, 342 UV/material points, seven GLBs and
  eight 4K maps. Maximum surface error 0.001165 mm and material error 0.00004184.
- Real Vulkan: 1,669 checks with GPU position and both normal-type readbacks
  under rigid/cable deformation. Maximum position error 0.000239 mm and
  geometric-normal error 0.000155. Zero floor holes in 1,009 projected probes.
- Native smoke: 194 checks; declared fields round-trip, invalid edits reject, saved rest
  restores identical robot PNG bytes, bent arm changes pixels, walk targets
  stay reachable, playback advances and the bank uploads once.

Device: **llvmpipe / software Vulkan**. These are correctness results, not
physical GPU speed or Android FPS. GIF playback rate is a presentation
choice, not a measured frame rate.

Initial failures are retained: the first floor had reconstruction holes;
the first walk pelvis position exceeded foot reach by 13.78 mm. Increased
projected footprint, fine floor/cable LOD and lowered walking pelvis fixed
those measured failures. Face bounds remain rectangular approximations;
extreme viewing angles can expose reconstruction edges. This prototype has
no character collision/controller, movement across the house, cable collision
physics or Android build. Silhouette, hands and armor layout need further
art direction.
