# R2 partial compute cache

The owner's Poco report from 0.1.2 confirms Android CPU/PSS APIs work without
errors, with approximately 1.10 GiB PSS. The last 120 LIE GPU reconstructions
have 210.94 ms median / 257.12 ms p95. Current cached presentation at 59–61 FPS
does not describe reconstruction speed. The report is preserved verbatim as
data in `checkpoints/R2_POCO_REPORT_0_1_2.json`.

## Reuse and invalidation

0.1.3 retains the immutable bank and the existing complete-frame signature.
Within a changed frame, each job gets a transform/deformation signature.
World positions, transformed geometric/shading normals and sample radii live
in the existing 96-byte projection records. No second world-sample bank is
allocated. Changed poses or cable frames dispatch just their sample ranges.
Jobs/LOD/layout changes, iris geometry settings and projection-buffer growth
conservatively invalidate every world record. Camera changes do not.

The world packet identifies the robot prefix and static architecture suffix.
A persistent 512-square static shadow map is combined with current robot
shadows using the same minimum-depth equation as before. Camera-only changes
reuse the combined map. Robot poses rebuild dynamic shadows while retaining
the static map. Light direction/position, static geometry, roof and layout
changes invalidate the appropriate maps. Disabled shadows skip generation;
reenabling after a pose change compares against the last actually built map.

Camera/geometry/material-support changes rebuild screen depth, ownership and
material accumulation for the full scene, preserving common robot/house
occlusion. Pure lighting, exposure, environment or unlit-inspection changes
reuse these buffers. Lighting and view-dependent specular remain current.
The whole-frame signature still skips all compute for identical packets.
This is not a cache of old views or an approximate frozen background.

Rigid inverse frames are computed once per changed frame into a small
per-instance buffer, avoiding repeated matrix inversions inside coverage
tests. Flexible cable coverage retains its original local deformation math.
The added allocation is 1,057,792 bytes (1 MiB shadow map + 9,216-byte rigid
inverse frames at 192 instances); mobile tracked total is 262,037,312 bytes.

## Measurements

`Copiar informe` includes `cache` decisions/cumulative counters, last per-pass
GPU milliseconds and p50/p95/sample counts over at most 120 measured compute
frames. Each per-pass distribution includes only frames where that pass ran;
skipped passes are absent, not reported as zero duration. GPU frame/age and
latest submitted cache decisions may refer to adjacent asynchronous frames.
Do not align their values or sum independently calculated pass percentiles.

Actual timestamps surround separate compute lists. Pinned Godot 4.7.2
`RenderingDevice::capture_timestamp` rejects markers inside a dispatched
active compute list; lists and resource dependencies supply the ordering.
Nanosecond conversion remains based on the pinned Vulkan driver implementation.

https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_device.cpp

## Verification and limits

`test_robot_cache_gpu.gd` compares actual 512-output/1024-internal GPU color
and depth against the unchanged old shader in `tests/fixtures/`. The fixture
is test-only and excluded from the isolated APK. Sixteen cases cover orbit,
pinchers, light power/direction, roof, cables, disabling shadows then changing
pose and reenabling them, unlit output, closer camera, actual locomotion and
exposure. All cases have exact color/coverage/depth equality on software
Vulkan, plus cache-hit/invalidation assertions; 157 checks pass.

The first run passed every image comparison but failed a test expecting
`project_depth` in the final lighting-only frame. That pass is correctly
skipped; the assertion now checks its recent measured distribution and the
last executed shading pass. This was a test failure, not a visual success
claim covering an untested state.

Touch/pixel/clipboard checks (262,172), motion (3,019), rig (3,734), process
metrics (17), agent (20) and 72 Python tests (one skip) also pass. Source
meshes are still collision-only, the same bank uploads once, and equations,
capture bytes, sampling density and output resolution are preserved.

Software results show substantial reuse during lighting changes and house
transforms/static shadows retained during walking. Project-depth and material
accumulation still dominate movement cost. Some camera/pose cases were slower
than the old shader on llvmpipe; no universal speedup or Mali FPS is claimed.
Per-case timings are single software samples with compilation/cache/order
effects, not a controlled physical-GPU benchmark. 0.1.3 needs a new Poco
report before its performance benefit can be established.

```sh
godot --path gpu_compute --script res://test_robot_cache_gpu.gd \
  --rendering-method mobile --audio-driver Dummy
```
