# LIE-27 — spherical joints and captured facial controls

LIE-26 articulated the captured anatomy with fifteen body bones. LIE-27 adds
thirty source-derived digit segments, forty-four invisible spherical joint
regions, connected orbital capture patches, and nine compact facial fields.
The compositor still draws captured samples. Native source meshes and the
diagnostic wire spheres never supply the character's rendered pixels.

## Geometry and influence

Each joint sphere is centered at a child pivot, with radius `1.8 * band`.
Only its connected parent and child can blend inside it. Outside the sphere,
the point keeps its rigid owner. The compact field is
`max(1 - sum(((p-center)/radii)^2), 0)^3`; its boundary gradient is zero.
Dual quaternion skinning transports captured positions, while the surface
Jacobian transports normals and footprints. The head ownership correction is
retained: cranial samples follow the head and only the cervical band blends.
The physics proxies have zero collision response; they are inspection/control
volumes, not a finished hitbox or ragdoll system.

Finger pivots come from principal axes of the source phalanges. Each of ten
digit controls curls three segments with authored gains `.75, 1, .65`.
The thumb uses the first metacarpal, proximal and distal phalanges. Axes and
limits are game controls, not medically validated ranges or thumb opposition.
Rigid skeleton captures keep their hand owner unless assigned to a digit.

Each eyelid patch reuses an exact native skin boundary. Seven rings converge
to an almond opening. Closed and midpoint targets follow a shell around the
native eyeball, with interior rings kept in front of that shell. Three views
at each of three blink states supply eighteen 160×160 orbital galleries.
Their gray, normal, depth, source position and triangle bindings are saved.
Samples follow sparse barycentric references. Common depth handles ocular
occlusion; closing never hides or deletes eyeball samples.
The orbital sample radius is `.68` capture pixels; this closes sparse
coverage gaps along the fully closed seam without altering eye visibility
flags or using an eye mask.

### Intact orbital skin and ocular materials (correction)

The initial eye-circle result was a coverage defect. Native triangles were
cut by their centroids but old captured skin points were removed using a
separate ellipse. These contours disagreed. The correction welds coincident
source positions for topology analysis, recaptures the native head from the
kept triangles, and joins the moving lid to their exact boundary. The cut is
limited to the actual eyelid area (18.5×9 mm radii). Thirty native head galleries
use 160×160 captures, plus three 512×512 perspective orbital galleries, and eighteen dense eyelid galleries use 160×160 within
a 45 mm capture window. The source file is never overwritten.

Rest and closed smooth normals share the native boundary normal. Their
interpolated shading follows the same facial/head transforms as position.
This removes the radial triangle shading in the original large patch.

Captured blink-state footprints are transported back to the rest tangent
plane before storage. Their symmetric covariance uses the previously unused
`gray_filter.yzw` of lid barycentric samples. The shader transports it forward
once, and limits each lid footprint to its deformed reference triangle. This
prevents closed-state captures from shrinking at the corners or extending
beyond their actual surface. Visible pixels still come from captured samples;
the high-resolution source mesh is not rasterized at runtime.
Fixed image grids can miss subpixel triangles. Adaptive local normal-ray
captures provide conservative coverage for these faces, constrained to each
deformed reference triangle. They preserve the captured material and smooth
normal while preventing a corner from uncovering the globe underneath.
Adaptive lid disks retain up to 64 projected pixels of support before the
triangle clip; the general 16-pixel cap cut off valid samples at face zoom.
Upper and lower contact rims overlap by an authored 0.2 mm at full closure.
This closes cracks between their independently sampled curved seam segments
while keeping the exact outer boundary and all native eyeball captures.
The corrected blink bank uses `connected-orbit-overlap-v3`.

The intact-skin state retains inner anatomy but suppresses its enclosed head
captures while skin is enabled. Its source-space lower boundary is 1.40 m;
twice each captured radius includes footprints whose support crosses that
boundary. Direct and barycentric captures use the same rule. Native eyeballs
are explicitly exempt. Disabling skin restores the original inner anatomy.
This is a head-region visibility rule, not a physiological containment test
or a runtime source-mesh intersection. Partial cuts are not implemented.

### Eyebrows and chin polish

Eyebrows use a tapered source-space pigment curve with fine directional fiber
strokes on the existing skin captures. They follow the captured surface under
`brow_up`, `brow_down` and head motion. The **Cejas** toggle accepts only a
boolean; invalid transactions reject all requested changes. The existing
320-byte parameter block carries the toggle in `reserved.w`, with no added
samples, buffers or draw passes. These are surface pigment, not standalone
three-dimensional hairs. Eyelashes are deliberately outside this change.

The native head gallery now interpolates the full uncut native skin normals
also used by the eyelid's outer ring (`shared-native-rim-v1`). Previously the
cut head triangles recomputed their own normals, leaving a shading mismatch
despite matching boundary positions. The migration updates 468,342 captured
normals and gallery hashes without changing captured positions or topology.

The chin lay below the previous head visibility boundary. Including it and
its captured footprint support prevents internal muscle from replacing skin
there. Three 80×80 native chin galleries at −35°, 0° and +35° supply 1,728
additional captured skin samples. They repair sparse lower-face coverage
from the original body bank while retaining its source-space neck weights.
Independent full-source skin rays protect the chin in neutral, jaw
opening, tilted-head and both 35-degree camera views. Output ownership must
be skin at every protected pixel, without missing coverage. The jaw channel
itself remains an approximate facial field rather than a mandible joint.

Actual eyeball captures carry material identity `geometry_front.w=10`, assigned
by native triangle BVH membership on the Internal layer. Skin/globe overlap
points are not relabeled as eye tissue. A separate 96-byte ocular uniform
provides warm-white sclera, a configurable iris, dark pupil and wet-surface
roughness. Iris fibers and the pupil use source-space positions on the curved
captured globe; changing the interior-tissue palette does not recolor the eye.
`eyes` contains `sclera`, `iris`, `pupil` RGB arrays and `roughness` in `.08–.6`;
invalid values reject the complete transaction.

Independent source-triangle rays classify skin and globe at thirteen poses
and camera orbits. The material boundary can be crossed by a projected sample
footprint, so exact labels are compared outside a conservative 16-pixel
footprint band. Inside that band, only skin or the actual eyeball is permitted.
Every protected pixel still rejects muscle, skeleton, other internal tissue
and missing coverage. A separate test requires zero visible ocular pixels at
full closure in frontal, tilted-head and both lateral views. Blue and green
iris changes must preserve every non-ocular output pixel exactly; another
test exposes internal tissues with skin disabled.

Facial fields use ellipsoids for the brows, lip corners and lower face, with
the same compact influence. They move soft tissue captures before the shared
head transform. The `jaw_open` channel currently translates the lower face:
it does not articulate a mandible or build a detailed oral cavity.

## Controls

Open `gpu_compute/lie27_regions_lab.tscn`, or select the LIE-27 workshop entry.
The anatomy bank is required at `gpu_compute/captures/anatomy27/`.
Use **Cuerpo / Rostro / Mano**, **Mostrar regiones**, facial sliders/presets,
and automatic blinking. Body FK, constrained two-link IK and walking remain.

| Control | Range | Effect |
|---|---|---|
| `left_thumb` … `left_little`, `right_thumb` … `right_little` | 0–90 degrees | Coupled three-segment digit curl |
| `blink_left`, `blink_right` | 0–1 | Independent connected eyelid closure |
| `smile`, `frown` | 0–1 | Authored lip-corner displacement |
| `brow_up`, `brow_down` | 0–1 | Authored brow displacement |
| `brows` | boolean | Show source-space eyebrow pigment on captured skin |
| `jaw_open` | 0–1 | Approximate lower-face displacement |

`command({"op":"set_values","values":...})` accepts a complete `face`
dictionary containing all seven facial keys. Unknown, out-of-range or
nonfinite values reject the whole transaction. Pose controls use `set_pose`
or the existing `pose` field. Revisions and stopped-frame reuse are retained.

## Reproduction

Use Blender 4.3.2, Godot 4.7.2 and NumPy. Acquire the source separately:
`3DAnatomyman_English.blend`, SHA-256
`a47d7ea9ae4082b793d4d45761c4c73db96707bb5f03c279b4133053c6c3e193`.
Prepare LIE-26 as documented, then:

```sh
blender -b --disable-autoexec --python tools/lie27_prepare_blender.py -- \
  --input /path/3DAnatomyman_English.blend \
  --base gpu_compute/captures/anatomy26 --out gpu_compute/captures/anatomy27
blender -b --disable-autoexec --python tools/lie27_eye_reference_blender.py -- \
  --input /path/3DAnatomyman_English.blend --root gpu_compute/captures/anatomy27
OPENBLAS_NUM_THREADS=1 python tools/lie27_reference.py \
  gpu_compute/captures/anatomy27 --fixture gpu_compute/fixtures/lie27-rig.json
blender -b --disable-autoexec --python tools/lie27_skin_eyes.py -- \
  --input /path/3DAnatomyman_English.blend --base gpu_compute/captures/anatomy27 \
  --out gpu_compute/captures/anatomy27_intact
# Use the corrected bank as anatomy27 before the following validation commands.
OPENBLAS_NUM_THREADS=1 python tools/lie27_reference.py \
  gpu_compute/captures/anatomy27 --fixture gpu_compute/fixtures/lie27-rig.json
blender -b --disable-autoexec --python tools/lie27_coverage_reference.py -- \
  --root gpu_compute/captures/anatomy27
# Existing intact banks can share the corrected normals/gate in place:
blender -b --disable-autoexec --python tools/lie27_polish_face_blender.py -- \
  --root gpu_compute/captures/anatomy27
blender -b --disable-autoexec --python tools/lie27_chin_capture_blender.py -- \
  --input /path/3DAnatomyman_English.blend --root gpu_compute/captures/anatomy27
blender -b --disable-autoexec --python tools/lie27_jaw_reference_blender.py -- \
  --input /path/3DAnatomyman_English.blend --root gpu_compute/captures/anatomy27
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path gpu_compute --editor --import --quit
godot --headless --path gpu_compute --script res://test_lie27_regions.gd
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus \
  --script res://test_lie27_gpu.gd
```

The source must remain offline for runtime. The generator verifies its hash.
Bank buffers have exact byte counts and SHA-256 checks. Original LIE-26
galleries and reference cases are provenance; their old sample ranges are
not current after orbital filtering. Only `layers` defines current ranges.
The separately distributed evidence package supplies the ready bank.

## Validation and remaining work

Recorded bank and local validation, 2026-10-12:

| Measurement | Result |
|---|---|
| Captured samples | 5,996,289 |
| Binding vertices / triangles | 12,309 / 7,678; source meshes stay offline |
| Runtime asset buffers | 481,007,632 bytes |
| Compositor allocation | 1,174,488,096 bytes, 1.094 GiB; engine overhead excluded |
| Increase over LIE-26 | 29,658,592 bytes, 28.285 MiB |
| Output / internal image | 512×512 / 1024×1024 |
| New orbital galleries | 18 at 160×160 plus adaptive source-triangle captures |
| Python suite | 72 tests, one external-asset test skipped |
| Godot CPU rig | 888 checks passed |
| Software Vulkan | 172 checks passed; five scripts compile cleanly |
| Maximum GPU / NumPy probe position error | 0.333 micrometres across nine cases |
| Chin source coverage | 122,605 protected pixels in five cases; zero inner leaks or missing pixels |
| Orbital source coverage | 1,189,821 protected pixels in thirteen cases; zero inner leaks or missing pixels |
| Native eye pixels, open | left 6,513; right 6,501 at internal resolution |
| Native eye pixels, closed | zero on both sides in frontal, tilted and ±35° views |
| Native eye pixels, left wink | left zero; right 6,501 |

These buffers are allocated by one laboratory instance. Sharing the asset
bank across many enemies is not implemented or measured in this change.

CPU tests cover compact boundaries, analytical derivatives, connected
ownership, cranial attachment and facial Jacobians. A source-derived fixture
checks all forty-five FK bones across nine poses. Independent NumPy probes
check GPU positions for direct face samples, digit samples and orbital sparse
references. Native eyeball BVH membership supplies an occlusion check: open
eyes must be visible, closed eyes occluded, and a left wink preserves the
right eye. The Vulkan runner captures the actual compositor, checks atomic
rejection, restoration, proxy alignment, a single asset upload and idle reuse.

Functional correctness does not establish production visual quality. Fine
facial motion, orbital rims, finger seams and existing body reconstruction
holes still need artist-authored corrective captures and coverage refinement.
Muscle physiology, detailed mouth/tongue, gore, cut surfaces, cloth, ragdolls,
shared enemy instances and physical GPU/mobile performance are out of scope.
The recorded Vulkan validation uses llvmpipe software rendering; its timings
must not be reported as game FPS or Android performance.

## Attribution

3DAnatomyman by Always3D, derivative of BodyParts3D © DBCLS.
Anatomical captures, region geometry, fixtures and evidence retain
[CC BY-SA 2.1 Japan](https://creativecommons.org/licenses/by-sa/2.1/jp/).
Keep this attribution and the source metadata with distributed derivatives.
