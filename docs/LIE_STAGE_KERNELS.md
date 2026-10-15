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

## Validated runtime and evidence

Runtime commit `e8152924e6b02a48510903c41a57b8acdb5b9084`, tree
`9f27b13da26cbb45cc222615ef279b456814e1ad`. All 18 triggered workflows passed.
Dedicated native/export run 38791156409, job 116615867301, artifact 11999349483.
Local: three Python regressions, 16 command checks, CPU rig 247, agent 25 and
18 compiled SPIR-V entry points passed. Actual Vulkan: 73 new Mobile checks,
16 command checks and all inherited regressions passed without leaked resources.

Depth was exact in tested comparisons; coverage IoU 1.0 and zero RGB error
against the actual 1.3 scene and across the three binaries in five views,
including the close oblique phone view. Area lights, raw/unfused material,
continuity/LOD and resizing comparisons also had zero RGB difference. The
shipping comparison completed all 81 events with nine complete GPU and CPU
samples per mode/kind and exact restoration. Its copied summary fit below
16 KiB. Rows are collected after each mode block, so the bounded live history
cannot evict earlier measured events (720 disjoint stage rows retained).

These nine-event-per-group p50 totals are **software Vulkan (llvmpipe)**:

| Change | Actual 1.2 | Actual 1.3 | Split 1.4 |
| --- | ---: | ---: | ---: |
| Camera | 295.671 ms | 352.645 ms | 267.786 ms |
| Light power | 84.507 ms | 118.879 ms | 79.286 ms |
| Light position | 139.405 ms | 173.121 ms | 120.383 ms |

The median reductions against monolithic 1.3 are 24.06%, 33.31%, 30.46% in
this software-device run. They establish neither Mali performance nor sustained
FPS. Negative evidence is retained: one split light-power event reached
317.791 ms total, including 246.105 ms in recovery reuse. Consequently that
group's split p95 is worse than 1.3 despite the lower median. The cause is not
established. Initial geometry warm-up does not separately prewarm every lighting
entry point; the captured first-use/outlier work is not discarded.

Appearance requested buffer/image bytes remain 280,581,000. Dedicated stages
need 1..17 storage-buffer declarations rather than the monolithic 32; this is
not a measurement of occupancy, spilling or driver program memory. Six native
descriptor-set rebuilds covered projection growth, resolution and visibility
lease changes. Bank uploads remained one for the new consumer, and the one
invisible collider and cached idle behavior passed.

`LIE_STAGE_KERNEL_NATIVE.json` preserves all comparisons, events and timestamps;
`LIE_1_4_ANDROID_BUILD.json` records the signed ARM64 APK; `LIE_1_4_ACCEPTANCE.json`
binds runtime, CI and artifact hashes. APK `LIE-Kernels-1.4.0.apk` is 58,410,530
bytes, SHA-256 `dc4fbda1487ca7dd3fd2164d2febb71996b1bf3b1a0a0bf2a021eda590fa5f03`,
package `org.lieengine.wallruntime.v140`, versionCode 14. Official template hash,
ZIP alignment/signature verification and immutable source-bank checks passed.

The initial implementation commit was superseded before native acceptance to
collect timestamps incrementally and exercise the full 81-event shipping path
rather than only the 27-event quick path. Its CI was canceled by the new head;
there is no failed native rendering run in this change. A local second staging
attempt correctly rejected an occupied staging directory; final checks used a
fresh directory. Physical Android performance is still pending the phone run.
