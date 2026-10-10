# LIE-14: invisible articulation, perception boxes and reusable captures

The experiment separates a rigid motion hierarchy, a six-face **invisible bound**
and the camera-facing image. A cylinder inside a box remains visually cylindrical.
Its box is used for conservative frustum rejection, not as visible geometry or as
its lighting normal. Shadows use an invisible analytic cylinder. No source GLB or
MeshInstance3D is loaded into the runtime lab.

## Asset and instance contract

One fixed, smooth Blender cylinder is photographed from 12 azimuths at -60, 0 and
+60 degrees elevation. Every camera view supplies one unlit grayscale/alpha pass,
one normal map and one depth pass. There are **no baked lighting permutations**.
The packer reconstructs object-local points using each actual capture matrix,
stores object-local unit normals and maps samples to stable finite surface nodes.
Mixed-depth boundary samples outside the analytic surface tolerance are rejected.

`master.json` records the six-face bounds, analytic collision dimensions, view
ranges/directions, sample digest, source-channel counts and finite surface nodes.
`master-samples.bin` contains two float32 vec4 values per valid captured sample:
local XYZ + neutral grayscale; local normal XYZ + local surface-node ID. The
buffer is uploaded once and shared by all three instances. Per-instance state is
a rigid orthonormal transform, node offset and material codes. Nonuniform scaling,
deformation and arbitrary imported shapes are outside this first contract.

The hierarchy has three hinged Node3D joints, each with a hidden rigid cylinder
collision shape. Local Y endpoints coincide with adjacent joint pivots. The
kinematic controls limit joint angles to +/-120 degrees. This is animation and
collision placement, **not** a dynamics solver with masses, torques or motors.

The box follows the part. The displayed reconstruction follows the real current
camera, using its perspective and transform. Captured XYZ determines per-pixel
depth and apparent size. A compact angular weight `max(2 dot(view, eye)-1, 0)^2`
includes every supported capture and tends continuously to zero at its boundary;
there is no abrupt closest-image switch. A nearest-depth pass precedes blending,
so samples behind foreground surfaces are excluded. Finite capture density, 2x2
point splats and a 25 mm depth fusion tolerance still permit holes, inflated edges
and sampling changes. This does not promise exact continuous views at every angle.

## Lighting

The LIE-11/13 finite diffuse transport retains RGB material filtering, absorption,
two frontier-only bounce generations and shrinking secondary radii. Articulation
transforms node centers/normals and rebuilds the reciprocal visibility/factor
cache using current cylinder positions. Pose changes therefore do not reuse an
obsolete static visibility cache. Primary-source visibility uses the matching
analytic cylinder solver on GPU, rather than the perception box.

The flat floor and wall sprite receivers use inverse perspective projection at
each output pixel, eliminating holes from a sparse receiver point grid. Their
analytic depth participates in the same nearest-depth comparison as captured
cylinder samples; this does not substitute analytic rendering for the cylinder.

The consumer splits total node irradiance into direct and indirect components.
It replaces direct node illumination with a per-sample calculation using the
captured normal, sample position, current primary-light codes, source radius,
conservative source cap and current cylinder visibility. The node's direct term
is subtracted before adding the pixel direct term; direct energy is not counted
twice. The remaining indirect field stays coarse and constant within each node.
Material absorption and tint are applied once at the visible receiver. A rotating
billboard does not rotate the object's normals; only the instance transform does.

Normals are light-independent geometry data. More lighting angles are not needed
for dynamic diffuse relighting. This gate does not add opaque metal specular or
directional indirect-light probes. Dielectric optics remain in the LIE-13 lab;
the new articulated consumer is not a unified glass/robot scene renderer.

## Acceptance and reproduction

```sh
blender --background --python tools/create_lie_master_fixture_blender.py -- /tmp/lie14-master.glb
blender --background --python tools/lie_capture_surface_blender.py -- --input /tmp/lie14-master.glb --out gpu_compute/captures/rigid_master --azimuth-steps 12 --elevations=-60,0,60 --resolution 128
blender --background --python tools/lie_master_pack_blender.py -- gpu_compute/captures/rigid_master
python3 tools/lie14_reference.py gpu_compute/captures/rigid_master
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute --script res://test_lie14_rigid.gd
godot --path gpu_compute res://lie14_lab.tscn
```

The float64 reference has independently clipped cylinder intervals and independently
computed skeleton transforms. It checks six moving/material/light cases against
actual GPU node irradiance and captured-pixel lighting probes. Two actual samples
from the same coarse node must receive different direct light from their normals.
An analytic perspective-ray oracle, independent of captured samples, checks body
silhouette and depth at five camera/pose configurations. Additional checks cover
quarter-degree view transitions, perceived size, native opaque sprite depth,
unchanged master upload count during movement and zero visible source meshes.
An actual camera facing away must reject all perception boxes, render no stale
captured body pixels and handle an empty capture task list safely.
Animation frames and actual viewport screenshots are exported with the report.

The lab includes touchable sliders for joints and orbit, pose/light/absorption
buttons and a pixel-normal toggle. Keyboard: arrows orbit/elevation, Space motion,
P pose, L light, X absorption, B direct/two-bounce, N normal detail.

## Budgets and limits

This is a 384-square mono perspective consumer, one cylindrical master, three
rigid instances and two procedural planar sprite receivers. Its GPU scratch buffer
reserves 64 tasks x 16,384 samples; pose updates also rebuild an O(N^2) CPU transfer
cache. It is a reproducible feature prototype, not a demonstrated Android speedup.
Native opaque depth is read but captured depth is not written back to the native
buffer. General skinned creatures, deformable fluids, asset streaming, stereo,
fully unified transparency and a Blender-scale authoring editor remain future work.

References: [Epic impostor captures](https://dev.epicgames.com/documentation/en-us/unreal-engine/impostor-baker-plugin-in-unreal-engine),
[PBRT diffuse reflection](https://pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection),
[Godot scene render data](https://docs.godotengine.org/en/stable/classes/class_renderscenedata.html).
