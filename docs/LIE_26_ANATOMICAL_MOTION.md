# LIE-26 — captured anatomical movement

LIE-25 rotated a cropped bust as one rigid object. LIE-26 captures the complete
3DAnatomyman body by segment and drives those samples from one authored game rig.
The original high-resolution meshes are used offline. Runtime draws captured
gray/normal/depth/XYZ samples, never the medical source meshes.

## Movement contract

- Fifteen semantic bones: pelvis, torso, head, two upper arms/forearms/hands,
  two thighs/shins/feet. Parent-child FK preserves source pivot offsets.
- Degree-valued manual controls with finite-value validation and joint limits.
- Two-link IK for either hand or foot, an explicit pole vector, a 140° hinge
  limit and a 160° ball cone. Unreachable goals return clamping and residual
  distance; the renderer does not pretend that they were reached.
- A deterministic procedural walking cycle plus corrective foot IK. The cycle
  does not require an external animation clip. This demonstrates the architecture;
  it is not an artist-authored locomotion controller or dynamic balance simulation.
- One actual `Skeleton3D`, fifteen invisible capsule proxies and an invisible
  ground collider follow the same evaluated rig. The proxies are coarse logic
  shapes, with collision response disabled in this laboratory. They are not the
  original anatomy and do not provide a tested game collision controller.
- All four tissue layers use the same rig. Skeleton objects have semantic rigid
  assignments; their samples never blend between bones. Soft tissues have two
  connected bone weights, saturating to a rigid transform in segment interiors.
- Quaternion antipodal correction and normalized dual quaternion blending
  transport samples. A spatial weight gradient supplies the local deformation
  differential: `F = R(w) + dP/dw * gradient(w)`. Tangent disks transform with F;
  oriented normals transform with its cofactor. At weight-field seams, sparse
  source-triangle bindings interpolate three once-deformed logical vertices.
  The triangle references are not rasterized or shaded. Camera depth, ownership and
  shadows consume the deformed samples rather than stale rest positions.

Cranial tissue above the cervical band attaches fully to the head, including
the face and eyes; a broad torso capsule cannot claim those points.

The capsule radius participates in the offline tissue assignment. Nearest bone
centerlines alone incorrectly associated side torso patches with forearms.
The regression tests preserve this distinction. Joint limits are authored game
limits, not medical range-of-motion measurements. Muscles do not contract or
slide physiologically; fingers are a rigid hand piece. Cloth, ragdoll, individual
fingers, joint pose corrections by an artist, cuts and exposed cut surfaces are
not implemented.

## Capture and memory contract

The source remains `3DAnatomyman_English.blend`, SHA-256
`a47d7ea9ae4082b793d4d45761c4c73db96707bb5f03c279b4133053c6c3e193`.
No checkout data, receipt or email is stored in this repository.

Each tissue is partitioned into capture segments before ray casting, so the
rest torso does not hide an arm surface needed later. Thirty-six views per
segment use azimuth steps of 30° and elevations −35°, 0°, +35°. Additional
localized catalogs capture actual bent source surfaces at neck, shoulders,
elbows, hips and knees from eighteen views. Those hits are mapped back to
source coordinates and use the common runtime rig for intermediate poses.
They are not pasted angle-specific screenshots or generated images.

The capture field and the runtime binding field are distinct authoring stages.
The measured bank uses the line field to establish immutable capture partitions
and bent catalogs; `lie26_rebind.py` assigns the later capsule field to those
existing source-space hits and to the independent native source vertices.
This preserves the captured gallery when a rig's weights are corrected.

The existing 80-byte sample stride is retained:

| Field | Meaning |
| --- | --- |
| binding.xyz / .w | Rest source XYZ / first bone ID, or barycentrics / negative source triangle code |
| normal_radius | Rest normal and captured disk radius |
| gray_filter.x / .yzw | Neutral gray / spatial gradient of second weight |
| material.xyzw | Roughness, second weight, second bone ID, tissue code |
| geometry_front | Rest oriented geometric normal and confidence |

Soft surfaces retain double-sided visibility after a fold, with lighting normals
oriented toward the viewer. Reconstruction covariance decreases at grazing
angles, reducing the silhouette inflation caused by a fixed screen-space radius.
Coverage remains imperfect. Sample shadows default to off for this movement
laboratory; direct light and runtime tissue colors remain active.

Fifteen 32-byte dual quaternion records update poses. The capture bank uploads
once and remains GPU-resident; a stopped pose does not recompute. The compositor
uses a bidimensional dispatch when sample groups exceed Vulkan's 65,535 minimum
per-axis count. The shader flattens both dimensions with bounds checks. Six
million samples are the explicit maximum; the integer EWA accumulation remains
below 32-bit capacity at that bound. This budget is not a mobile performance
recommendation.

`master.json` retains layer ranges, rig, source license, gallery names and buffer
hashes. The consumer checks byte counts, hashes, finite coordinates, integral
bone/tissue IDs, weight bounds, normal lengths, unit pose quaternions and valid
dual quaternion orthogonality before dispatching.

## Reproduce

Acquire the free source separately, with its CC BY-SA attribution. With Blender
4.3.2, NumPy and Godot 4.7.2:

```bash
blender --background --disable-autoexec --python tools/lie26_prepare_blender.py -- \
  --input /absolute/path/3DAnatomyman_English.blend \
  --out gpu_compute/captures/anatomy26 --capture-field line --no-references
OPENBLAS_NUM_THREADS=1 python3 tools/lie26_rebind.py gpu_compute/captures/anatomy26
blender --background --disable-autoexec --python tools/lie26_refine_skeleton.py -- \
  --root gpu_compute/captures/anatomy26
blender --background --disable-autoexec --python tools/lie26_bind_joints.py -- \
  --root gpu_compute/captures/anatomy26
blender --background --disable-autoexec --python tools/lie26_prepare_blender.py -- \
  --input /absolute/path/3DAnatomyman_English.blend \
  --out gpu_compute/captures/anatomy26 --references-only
godot --headless --path gpu_compute --editor --import --quit
godot --headless --path gpu_compute --script res://test_lie26_rig.gd
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus \
  --script res://test_lie26_motion.gd
python3 tools/lie26_compare_native.py gpu_compute
```

Use `--reuse-source --reuse-captures --no-references` to repack an existing gallery
without repeating its ray casts. Rebind/refine before adding sparse joint
bindings; sparse binding rejects an already bound bank. Atomic `.pending.npz` archives are not inputs;
only closed final archives are consumed. Rebinding is idempotent for the skeleton
footprint adjustment. The complete high-resolution source is retained offline for independent
references. Only the sparse seam triangles are uploaded as invisible bindings.
For a later weight correction, `lie26_rebind.py gpu_compute/captures/anatomy26
--keep-sparse` also updates those logical vertices while preserving their triangle
and sample references.

Open `res://lie26_motion_lab.tscn`, or select **Movimiento anatómico · FK / IK**
in the workshop. Controls include layer visibility, palette, orbit, light,
individual joints, pose presets, walk/pause and a right-hand IK target. The
command API supports `snapshot`, atomic `set_values`, and merging `set_pose`:

```json
{"op":"set_pose","values":{"right_elbow":90,"left_knee":45}}
```

```json
{"op":"set_values","values":{"targets":{"right_hand":{"position":[-0.25,1.2,0.36],"pole":[-0.5,0.8,0.5]}}}}
```

`expected_revision` rejects stale mutations. `pose`, `targets`, `mode`, `playing`,
`time`, `speed`, layer/color/camera/light state can be changed atomically. The
effective joint transforms and IK residuals are available in `lab.evaluated`.

## Verification and evidence

The fixture contains independent offline FK results for five source-axis poses.
Tests cover limits, finite values, reachable and unreachable hand/foot targets,
the complete gait cycle, GPU/CPU positions, rigid bones, shared Skeleton3D and
proxy pivots, hidden tissue ownership, exact rest restoration, one asset upload,
and a dispatch larger than the previous one-dimensional Vulkan limit.

`lie26_compare_native.py` uses perspective rays against the original source
triangles after an independent offline pose evaluation. Its 1024² source rays
are reduced to 512² with the same four coverage samples as the Lie output.
It compares silhouette,
linear tissue palette after display conversion, source depth and joint crops.
Its thresholds are fixed before evaluation: full silhouette IoU ≥ .98, joint
crop IoU ≥ .96, RGB MAE ≤ .03, depth MAE ≤ 3 mm and depth p95 ≤ 8 mm.
These measure agreement with this authored source rig, not medical realism,
artist quality, physical GPU speed or arbitrary camera/pose coverage.

The delivered evidence contains the exact bank, real GPU frames, comparisons,
source metadata and logs. Measured delivery: 5,828,568 samples; 444.68 MiB sample buffer; 1,091.79 MiB
own compositor allocation; 11,412 additional logical vertices and 6,142
triangles bind 26,787 seam samples. All 247 rig checks and 99 Vulkan functional
checks passed, as did 66 Python tests with one external-master skip.

**Visual acceptance did not pass.** Global silhouette IoU for skin cases ranges
from .9721 to .9782; the bone case is .9191, against the .98 target. Joint patches
and bone depth outliers also remain outside their targets. Sparse joint bindings
correct seam transport, but the point reconstruction still has holes and edge
inflation. This branch is a functional movement prototype, not a visually
accepted release. These failures are preserved in the report and evidence.

See the detailed measured results in that report. Software
Vulkan validation does not establish physical GPU or Android frame rates.

## Attribution and references

3DAnatomyman by Always3D, derived from BodyParts3D © DBCLS, modified by
segmentation, capturing, authored rigging and tissue coloring for Lie. License:
[CC BY-SA 2.1 Japan](https://creativecommons.org/licenses/by-sa/2.1/jp/).
[Source](https://always3d.gumroad.com/l/haJWL). Derivative anatomy assets retain
attribution and ShareAlike. These terms do not automatically change the engine
code's separate license.

The blending method is based on [Kavan et al., Skinning with Dual Quaternions,
2007](https://users.cs.utah.edu/~ladislav/kavan07skinning/kavan07skinning.html).
This implementation does not import their downloadable shader code.
