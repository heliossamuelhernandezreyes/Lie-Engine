# LIE 2.1: camera work, resolution and graphics footprints

The camera reconstruction is the next performance target. The supplied LIE 2.0
Mali-G720 MC7 report showed camera intervals around 60 ms in every submission
mode, while the scalar-power response cache reduced power-only updates from
20.00 to 12.25 ms. Removing stage timestamps and using lean submission did not
substantially improve camera reconstruction. Its transcribed summary is retained
in `checkpoints/LIE_CAMERA_RENDER_MALI_BASELINE.json`. These observations do not isolate
Godot overhead or establish a GPU bandwidth bottleneck.

This experiment creates a reproducible Android comparison. It does **not**
establish the requested large physical-device FPS improvement. The new APK has
not been run on the physical Mali in this environment.

## Baseline and identity

- Parent: `0458d7966270f7bdcb193ba7cf8b714da1bf2df0`, the documentation follow-up
  to the LIE 2.0 power-response runtime.
- Godot `4.7.2.stable.official.ed1daf0bf`; Android ARM64, version code 22,
  `org.lieengine.wallruntime.v210`, version `2.1.0-camera-render`.
- One unchanged 41,700,560-byte, 80-byte-record attributed source bank:
  `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
- Output remains 720 × 720. The accepted initial internal size remains 1080.
  The compute backend remains the default.
- The same source IDs, transforms, invisible collider, surface queries,
  active visibility, direct-light response and indirect-light consumer remain.

## Two independent changes

The resolution selector accepts 720, 810, 900, 1080 and 1440. Compared with
1080², 810² processes 43.75% fewer internal pixels and 720² processes 55.56%
fewer. This removes existing supersampling; it is a quality/performance tradeoff,
not an equivalent-resolution acceleration. Pixel-count reduction does not
predict proportional total speed because source projection and other work remain.

`graphics` replaces only the two footprint raster passes. Projection keeps the
existing equations and projected records. Two **auxiliary triangles per captured
footprint** cover its original integer rectangle; the fragment shader still
tests the original disk and computes its original depth and material terms.
This path does draw triangles for reconstruction, although source asset meshes
remain invisible. It is not a triangle-free hardware implementation.

R32F hardware MIN blending resolves linear depth. Two RGBA32F attachments use
ADD blending for the original eight nonnegative integer material sums. Original
owner and source-visibility atomics remain. A final compute resolve writes the
original buffer ABI. This is not native depth testing and does not remove the
lighting traversal or the original 80-byte source bank.

The attachments are allocated only when graphics is first requested and cost
`36 * internal_size² + 32` additional requested bytes: 41,990,432 bytes at 1080.
They stay resident when switching back to compute, until resize/release. Fixed
allocation accounting and requested bytes are not physical GPU residency.

Float32 integer blending is exact only while all accumulated channels stay
below 2²⁴. A GPU guard records violations. The benchmark performs an explicit
untimed preflight at the initial 1080 view: SHA256 of the complete original depth,
owner and eight-channel material buffers, plus the precision guard. A mismatch
excludes graphics from the comparison. This initial-view validation is not a
proof for every camera pose or arbitrary bank.

Before allocating attachments, the native module queries the active Vulkan
physical device's R32F and RGBA32F blend format capabilities through public
Vulkan 1.0 functions. It borrows the RenderingDevice handles only for that
read-only query on the render thread. Unsupported formats fall back to compute
and the report explicitly skips graphics; the three compute comparisons continue.
The optional backend is experimental when selected manually as well.

## Phone procedure

1. Install **LIE Camara 2.1**. Its separate package can coexist with 2.0.
2. Use the same scene/view as the 2.0 measurement, or leave the initial view.
   Every comparison restores its starting state.
3. Press **Comparar GPU**, let the test finish, then **Informe** and copy the text.
4. Inspect camera p50/p95 for `Referencia 1080`, `Compute 810`, `Compute 720` and
   `Gráficos 1080`. Inspect the images at 810/720 as well as the timing.

The standard run rotates four modes across four rounds: 144 measured events,
12 per mode/event kind, plus 160 fixed warm-up events. Camera, power-only and
light-position events remain separate. All modes retain the whole appearance
GPU interval. Stage timestamps, lean submission, screen tiles, compact shadows
and visibility-stream alternatives are held off; power response is held on.
The current view, bank, other options and light state are common.

Unsupported graphics yields 108 measured compute events plus the recorded
unsupported probe. Requested and available event counts, skips, telemetry
boundaries and restore status remain explicit. The preflight buffer readbacks
are outside measured events and precede fixed warm-up. Cold/initial builds and
warm-up histories are retained separately; measured spikes are not removed.

Full histories are saved as `user://lie-camera-render-last.json`; the copied
report preserves summary, scope, preflight and skips. Presentation FPS may
include cached images. GPU intervals are not input-to-photon latency.

## Local evidence and failures

The machine-readable final evidence and APK proof are in
`checkpoints/LIE_CAMERA_RENDER_NATIVE.json` and
`checkpoints/LIE_CAMERA_RENDER_APK.json`. Tests use the genuine attributed bank
and an actual Vulkan device: **llvmpipe LLVM 20.1.2**, which executes in software.
It is neither a physical GPU nor Mali performance evidence.

Final software camera results, 12 whole-interval events per mode:

| Mode | p50 ms | p95 ms |
| --- | ---: | ---: |
| Compute 1080 | 133.32 | 182.73 |
| Compute 810 | 90.15 | 135.62 |
| Compute 720 | 79.46 | 161.51 |
| Graphics 1080 | 424.19 | 491.78 |

720 is about 1.68× faster in this software run, with image differences.
Graphics is slower, so it remains off by default. The test scene after the
grazing/alternate-access cases is recorded in the JSON; these numbers do not
reproduce the full, truncated phone scene and must not be converted into a Mali
FPS prediction. Final acceptance: 76 Vulkan checks, 33 camera command checks,
12 native-probe checks, 247 rig checks, 25 agent checks and 60 Python regressions.

Acceptance compares the accepted 2.0 consumer against new compute1080, tests
resolution roundtrips and bank reuse, and compares exact depth, owner and all
eight material channels between compute and graphics in five cases. The cases
include frontal, close oblique, grazing, selected-block and direct-source
paths. It also exercises the unsupported-format branch with real compute
rendering, benchmark completeness, cancellation/restore and idle reuse.
Image errors at reduced resolution are retained; 720 has visible coverage/detail
loss in the default wall view. Keeping the source bank does not make the final
images equal.

The first native run passed its three image/raster comparisons but failed the
timing acceptance because whole-interval contexts omitted `raster_backend`:
reference1080 and graphics1080 were merged into one group. Its failed raw
evidence is preserved as `checkpoints/LIE_CAMERA_RENDER_FIRST_NATIVE.json`.
The final context includes the backend; every supported group must have the
complete event count. The software timing result for graphics is also retained
even though it is slower.

An intermediate JSON-control correction also failed acceptance: integral JSON
numbers were still compared by the array's strict Variant type, and adding an
empty `values` member changed non-value command dispatch. That failed native
run is retained in `checkpoints/LIE_CAMERA_RENDER_WIRE_FAILURE.json`. The final
policy accepts only supported exact integral numeric values, canonicalizes
resolution state to integers, and preserves non-value requests. The command
suite now covers the actual JSON parse/control path. Partial graphics resource
creation is cleaned up before retry; a final quick Vulkan run repeats all
correctness cases after that cleanup change.

Reproduce with:

```sh
python -m pip install -r requirements-ci.txt
python -m unittest discover -s tests -p 'test_lie_camera_render.py' -v
python tools/lie_wall24_shader.py
python tools/lie_hardware_build.py --cache /tmp/lie-native-deps --platform linux.x86_64
python tools/lie_wall24_android_build.py --stage /tmp/lie-camera-ci
godot --headless --path /tmp/lie-camera-ci --editor --import --quit
godot --headless --path /tmp/lie-camera-ci --script res://test_lie_wall24_commands.gd
godot --headless --path /tmp/lie-camera-ci --script res://test_lie_hardware_probe.gd
godot --headless --path /tmp/lie-camera-ci --script res://test_lie26_rig.gd
godot --headless --path /tmp/lie-camera-ci --script res://workshop/test_lie_agent_session.gd
xvfb-run -a godot --path /tmp/lie-camera-ci --rendering-driver vulkan \
  --rendering-method mobile --audio-driver Dummy --script res://test_lie_wall24_mobile.gd
```

`LIE_CAMERA_QUICK=1` reduces timing to one round; correctness checks still run.
The dedicated workflow also builds the pinned ARM64 module, exports with the
verified official template, normalizes the manifest, signs and verifies the APK,
checks ZIP alignment and validates the exact bank and 16 KiB ELF load alignment.

## Next decision gates

At 59.79 ms, the camera interval alone corresponds to 16.7 updates/s. Reaching
60 camera updates/s requires about 3.59× acceleration, before any non-overlapped
frame cost. Reducing 1080 to 720 provides at most 2.25× acceleration of a purely
pixel-proportional component. It cannot by itself justify a 60 FPS promise.

Use the phone report to choose the next implementation:

| Observed result | Next work | Acceptance requirement |
| --- | --- | --- |
| 720/810 improves camera cost, with acceptable image loss | Explicit interactive quality mode; then projected-error LOD/aggregation of source footprints | Silhouettes, holes, normals and material response across motion, not just a static average error |
| Graphics passes exact validation and improves same-resolution camera p50/p95 | Optimize attachment footprint, material accumulation and remaining atomics | Same 1080 interval, source bank and image; cold builds, memory and sustained physical-device cost retained |
| Both paths remain too expensive | Prototype per-box layered depth/normal/material views and sparse residual samples | Disocclusion, oblique faces, thin geometry, self-shadowing and source identity; this is a new representation |
| Engine overhead remains a plausible material cost | Build a minimal native Vulkan Android viewer using the same bank, SPIR-V, buffers and event script | Separate GPU interval, CPU submit and presentation; compare identical work on the same phone |

The layered-view representation and standalone native Vulkan viewer are **not
implemented in this change**. Moving the same shaders to another engine does
not reduce their source/pixel work. A native viewer is the controlled way to
measure whether removing Godot changes the bottleneck before porting the product.
