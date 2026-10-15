# LIE 1.4: independent stage kernels

The phone's 1.3 report measured CPU control p50 0.954 ms, but instrumented GPU
p50 63.314003 ms on camera changes, 24.505233 ms on power changes and
49.433849 ms on moved lights (33.564232 ms world visibility). These are three
samples per diagnostic kind at 1080, two lights, camera yaw -105.747891,
elevation 3.54137, distance 0.6. They are not a controlled comparison with 1.1.

`tools/lie_wall17_shader.py` derives 18 independent entry points from accepted
1.3 equations. It removes unrelated main branches, unreachable helpers and
unused descriptor declarations. Workgroup arrays occur only in bounds stage
18. Original helper equations remain byte-identical. Stages 2/3 and 8/9 retain
compile-time constants so the shader compiler can also eliminate their shared
source branches. No samples, materials, primitive tests, source identities,
indirect-light transport, hole recovery rules or invisible colliders change.

The effect owns a shader, pipeline and precise descriptor set per stage.
Sets rebuild when projection buffers, output resolution or borrowed visibility
leases change. Borrowed transport/visibility RIDs stay owned by their original
providers. Shutdown frees descriptor sets before pipelines/shaders and buffers.
No additional surface buffer is allocated; pipeline/driver memory is not
included in requested RID buffer-byte accounting.

Three execution modes share the same resident scene: actual 1.2 monolithic
binary (`legacy`), actual 1.3 monolithic binary (`monolithic`), and 1.4 dedicated
kernels (`split`). The hierarchy queue ordering is unchanged, deliberately
isolating the compiled-kernel change. This does not prove any particular Mali
register pressure, spilling, occupancy or cache-locality diagnosis.

## Paired phone diagnostic

`compare_kernels` captures the current state, disables diagnostic work counters,
and runs the same nine events in each mode: three camera, three power and three
light-position changes. Each mode block first restores the identical scene,
invalidates visibility and performs an unmeasured geometry rebuild. The changed
light is cold after position changes; the untouched light retains its cache.
Shipping comparison rotates mode order across three rounds (81 measured events,
nine per mode/kind). `quick=true` uses one round (27 events) for native tests.
Only explicitly recorded event serials enter paired sums. Warm-up, restore and
idle frames are excluded. Each group reports GPU sum percentiles, stage times
and separate CPU command time. Cancellation and success restore exact state.
Full event and timestamp evidence is persisted separately from compact copy.
This is not thermal control, a sustained FPS benchmark, or image latency.

`Comparar GPU` starts the paired run; `Informe` exposes the three comparisons.
The individual current-mode diagnostic remains available in the control panel.
Devices below the existing 32-storage-buffer support gate retain 1.2 fallback;
they do not claim to run the split variant.

## Validation status

Local: three Python regressions, 16 command checks, CPU rig 247 and agent 25
passed. Native Vulkan image/depth tests and signed Android export are required
before delivery. Physical Mali speed is unknown until the user runs the paired
comparison. Native software-Vulkan timings must not be extrapolated to Mali.
