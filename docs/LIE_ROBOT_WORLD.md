# R2 · robot exploration and collision world

R1 now traverses a modular house rather than only walking in place. The same
native compositor renders the robot and architecture into shared depth and
shadow buffers. Original source meshes are not drawn. This is an experimental
Godot laboratory. The later Android touch prototype is documented in
`LIE_ROBOT_ANDROID.md`; this remains an unfinished experimental scene.

Branch `experiment/lie-robot-world` is based on R1 commit
`74d0f63918151ad79b7c65b258afdcf406995a07`. It is stacked on R1 / PR #33,
which itself depends on LIE-28 / PR #28. No main merge is implied.

## Changes to the robot

- Angled chest panels taper toward a narrower abdomen.
- Two anterior fingers close against a posterior thumb; all six segments still
  reuse the same shaft master. The laboratory adds a dedicated `hand` focus.
- Shoes orient their detailed face upward and place the source sole on the
  ankle target's ground plane.
- Thin shafts get 320-resolution capture and retain polygon ownership during
  voxel reduction. This avoids deleting entire cylinder facets. Coarse shaft
  spacing is six times fine spacing; face bounds still clip coverage.

Geometry, original GLBs, 4K maps and the original R1 bank remain unchanged.
The refined capture is a separate `captures/robot_refined` bank. The standalone
robot editor prefers it when present and can still restore the old R1 bank.

## Shared world and budgets

`lie28_building_assembly.gd` extracts the existing LIE-28 layout without
changing its module positions. The robot scene instances it at scale 1.2:
the interior is 4.8 × 3.6 m, wall height 2.88 m and doorway width 0.90 m.
The existing lintel sets the effective opening height. Four captured courtyard
tiles form a 12 × 12 m support area.

`tools/lie_robot_world_prepare.py` validates both source bank hashes and
combines all refined robot samples with LIE-28's existing coarse level for
the seven construction masters used by the house. It converts 80-byte
construction samples to 96 bytes, preserves positions/normals/albedo/roughness
and face bounds, supplies zero metallic/emission, copies the geometric normal
to shading normal and offsets material zones to avoid the robot's coating tint.
It does not regenerate or claim HD construction assets from concurrent work.

The combined bank has 457,190 samples / 43,890,240 bytes, below the 64 MiB
integrity guard. One bank is resident per scene lifetime. With no roof the
scene has 150 rendered instances: 79 robot parts and 71 environment instances.
With the roof it has 162. The world alone supports at most 192 instances /
1,300,000 sample invocations; existing laboratory defaults remain 128 / 750,000.
Robot output remains 768 × 768 with a 1536 × 1536 reconstruction target.

## Movement and foot contact

`lie_robot_controller.gd` is a Godot `CharacterBody3D` with a 0.35 m radius /
1.76 m height capsule, gravity, acceleration and collision sliding. Native
widgets, WASD/arrows, Q/E, space, camera dragging and external agents use the
same validated `command()` path. Diagonal input is normalized. The capsule
approximates the body; hands, armor and cables have no individual colliders.

Gait phase advances from actual horizontal distance, not elapsed animation
time. A blocked character stops advancing its gait. Foot targets remain fixed
in world X/Z during stance; swing interpolates to a forecast landing with lift.
Ground rays use a bounded height interval. Landing prediction raises its swept
capsule 60 mm so the source floor's 20 mm threshold does not falsely shorten a
step. This is calibrated for this flat courtyard/house, not general stair or
terrain locomotion.

The controller produces semantic pose channels and foot targets. The existing
`lie26_rig.gd` remains the only bone FK/IK solver. Rigid instances and transported
cable frames then receive the character's world transform. Foot orientation
follows body heading; position locking is not full contact/friction physics.

Architecture collision uses the exact original source triangles, including
door/window openings. These triangles are collision-only `ConcavePolygonShape3D`
resources. Rendered instances and colliders share one layout and scale. Four
invisible courtyard guards bound this test area; their separate collision layer
constrains the character while the camera can leave that area.

The third-person camera sweeps a small sphere against actual architecture and
retracts before entering a wall. Overview is an inspection camera. Roof display
also adds/removes the corresponding physical surfaces.

## Restore, control and reproduce

Obtain `R2-Robot-Casa.zip` identified in
`checkpoints/LIE_ROBOT_WORLD_CHECKPOINT.json`. Verify its size/SHA-256 and copy
its `captures` contents into `gpu_compute/captures`. The package includes both
refined and combined banks, editable robot source, original building masters,
native saved states, actual journey images, GIF and failure evidence. Source
code and complete generator instructions stay in Git.

```sh
python tools/lie_agent_launch.py --godot /path/to/godot --lab robot_world \
  --directory /absolute/path/new-r2-session
python tools/lie_workshop_client.py --directory /absolute/path/new-r2-session \
  --command '{"op":"set_values","values":{"move":[0,1],"playing":true}}'
```

Pause for deterministic commands and then queue exact simulation ticks:

```json
{"op":"advance","ticks":60}
```

`advance` returns `target_tick`; poll snapshots until `motion.remaining_ticks`
is zero and `state.motion.ticks` reaches that target. It accepts integer-valued
JSON numbers from 1 to 600. It rejects active playback or an existing queued
step job. Invalid edits, stale revisions, unsafe filenames and attempts to
restore the capsule inside a wall reject atomically.

Saved state includes position, heading, velocity, phase, travel, tick counter,
all foot anchors/targets, inputs, camera, material and playback fields. The
bridge survives navigation between the world and the existing robot editor.
Assembly poses, curve packets and the environment are observable in snapshots;
there is no arbitrary code-evaluation endpoint.

```sh
blender --background --python tools/lie_robot_prepare_blender.py -- \
  --materials /absolute/path/original-4k-maps --bank-name robot_refined \
  --bank-only --refine-shaft
python tools/lie_robot_verify_captures.py --materials /absolute/path/original-4k-maps \
  --bank-name robot_refined
python tools/lie_robot_world_prepare.py
godot --headless --path gpu_compute --script res://test_robot_world_motion.gd
godot --path gpu_compute --script res://test_robot_world_gpu.gd --audio-driver Dummy
python tools/lie_robot_world_agent_smoke.py --directory /absolute/path/new-r2-session
```

Rebuilding needs the separately saved original R1 source masterkit/maps and
LIE-28 source bank. For a synchronized workspace, keep live inbox/outbox files
in a private temporary directory, run launcher/client together and stage
completed evidence after closing that disposable session.

The editable `R2-Robot.blend` and GLB come from native authoring packets. Its
16-phase Blender animation is the rig preview walk; the 32-frame GIF and
`r2-journey-assembly.json` record actual world collision movement separately.
GIF timing is a presentation choice, not measured engine FPS.

## Verification and retained limits

Exact measured results and saved file identities are in the checkpoint. Tests
cover JSON persistence semantics, atomic rejection, a blocked wall, passage
through the doorway, floor support, window/back/east walls, courtyard bounds,
intermediate curb poses, stance position locking and camera obstruction.
The native session also restores byte-identical compositor PNGs both before
movement and after navigating away from a saved interior state.

GPU acceptance reads actual positions and both normal types back from Vulkan,
checks finite shaded pixels, combined budgets, floor interior coverage and
collision/rendered wall depth. Interior wall probes require agreement of four
independent physics rays in a two-pixel cross on the same source plane.
Brick/silhouette boundary depth differences are counted separately and retained,
not presented as exact geometry agreement. Approximate support bounds, coarse
construction capture, 512-pixel shadow maps and analytic studio reflections
remain visible quality limits.

Tests ran on **llvmpipe software Vulkan**. They establish behavior/correctness,
not physical GPU speed, Android performance or enemy-count capacity. There is
no cable elasticity/collision, grabbing system, jump or combat. The subsequent
touch APK does not establish physical Android GPU performance.
Further art direction and production locomotion remain work.

Failures retained in the package include a collider property error, integer
JSON tick rejection, an overly strict double comparison, the shortened curb
step, thin shaft facet loss, and brick-edge depth probes. They are evidence for
the next iteration, not discarded successful-looking renders.
