# Stable sample identity and persistent source visibility — WALL11 / 0.8

Base: `b86087524d0abefb0fba535b6dd887f8202a2348` / WALL10.
Source bank remains
`ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
No captured position, normal, RGB, radius, subset, pose, tint, field graph,
light-energy budget or collision shell is edited. This stage makes existing
source lookup and fine visibility reusable; it does not add a new BSDF or
area emitter.

## Two different identities

`lie_sample_identity.gd` validates the existing asset contract once, indexes
assets by their stable compiled ID and resolves `(asset ID, LOD, local sample)`
to the original source index and 80-byte offset. Instance identity is separate
from the neutral master. Read-only `sample_address` uses the same validated
command path; unknown assets, nonintegral numbers and invalid ranges fail
without changing scene revision. This does not instantiate a Sprite2D per
sample or search for photographs at render time.

`lie_shared_sample_buffers.gd` now assigns a monotonically increasing
generation to each actual RD bank allocation. Resident handles contain bank
key and generation; `resolve()` rejects stale generations, wrong devices and
out-of-range IDs without file I/O, hashing, scanning or GPU readback. Existing
bank-sharing callers remain compatible. Semantic IDs persist across reloads;
the allocation handle must be reacquired. Generation-guarded release also
rejects an old handle instead of freeing a newly reloaded bank. A disk miss still has loading cost.
This stage does not implement world streaming, eviction policy or prefetch.

## Direct workgroup ownership

The common identity helper validates job bounds and builds `(job, local start)`
records for 64-thread source groups. The shader maps each lane directly to its
original compact projection index. It replaces the per-sample binary job search
when enabled; real source counts and all output indices remain unchanged.
Only the last group of each job is padded (fewer than 64 lanes per job).
All three resident LOD schedules are compiled at initialization. Layout-specific
job lists stay in the wall adapter. The comparison switch retains the old
search path. Rendering speed must be measured; fewer lookups alone do not
establish an FPS increase.

## Camera-independent mutable cache

`lie_shared_shadow_cache.gd` owns a GPU buffer leased by RD, bank SHA,
reference SHA, scene SHA and both BLAS packet SHAs. The same reference index always binds the same
captured source ID and instance in this immutable domain. A different source
selection gets a different domain. The source index and instance are never
replaced by a screen pixel. Projection `normal.w`, previously an unused front
cosine after culling, now stores the exact integer reference index as a float;
this is below the 24-bit exact-integer limit for the accepted bank.

The buffer has a 256-byte header and 12 bytes per reference: two visibility
words plus an independent eight-channel validity mask. A valid zero shadow
is still a cache hit. Visibility retains WALL10's 8-bit channels and 7-bit
eighth channel, with the same source-center anchor, 2.5 cm reach and 0.3 mm bias.
The immutable BLAS and coarse field are unchanged.

The actual GPU light packet drives invalidation, avoiding a CPU snapshot race:

1. A tiny compute pass compares the eight current point-light positions,
   source count and query reach/bias with the shared header.
2. Changed channels clear only their validity bits over the reference bank.
3. Winning source projections reuse valid channels and trace missing channels.
4. Existing direct/indirect appearance consumes the same packed results.

Color, power and cutoff radius do not change this bounded geometric query.
They still update irradiance and transport as required. Zero-power sources
skip tracing and do not certify previously missing visibility. Moving a light
invalidates that light across the domain; this stage does not yet cull the
invalidation to a smaller spatial region. Different view light configurations
are serialized by these GPU keys and barriers; alternating them can thrash
the cache but cannot safely reuse incompatible results.

Known surface entries survive camera changes, size changes and geometry
reprojection. Newly visible source IDs are queried on demand. Identical views
share mutable results as well as the immutable bank and BLAS. Uniform sets
release their borrowed cache RID before its last lease is freed. Metadata
inspection is mutex-protected; mutable GPU writes use RD compute barriers.

Default diagnostics are off. Optional per-light hit/query counters add atomics
only when explicitly enabled. Diagnostic readback fetches small control/header
buffers, not a full-frame source map, and never drives runtime lighting.

## Verification and limits

Local: two new Python reference/generator tests, five prior source tests,
ten prior asset tests, rig 247, agent 25, 33 source-address/schedule checks and
13 strict command checks pass. Both new shaders compile to SPIR-V. The first
shader import used GLSL's reserved word `active`; the failed compiler log was
retained and the variable renamed before native acceptance. A fresh staged
import displayed Godot's popup error while reporting the failed shader; a
fixed reimport is clean. The first fixture serializer rejected numpy float32
scalars; explicit scalar conversion fixed it without changing the oracle.
An early stage attempted to copy a test still being authored; the clean stage
was rebuilt after all dependencies existed.

Native acceptance executes the actual cache include against exhaustive float64
disk references, including fractional visibility and eight lights. It checks
cold/warm, radiometry, individual light movement, zero power, the eighth slot,
metric invalidation, uncached equivalence and real bank reload generations.
Full-wall acceptance compares to WALL10, direct-block equivalence, camera and
size reuse, two independent viewports, incompatible lights, source-domain
isolation, exposure, idle and lease lifetime. Native results and signed APK
identity are recorded below and in
`checkpoints/LIE_PERSISTENT_IDENTITY_CHECKPOINT.json` and
`checkpoints/LIE_PERSISTENT_IDENTITY_NATIVE.json`.

## Accepted results and APK

Runtime `cd70e6bca6079785f736ea5aa169b0a8b55fcf2f`,
[run 38700372874](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38700372874):
126 common GPU cache checks across ten disk-reference scenes, 59 full-wall
checks, 33 source-identity checks and 13 command checks pass. The inherited
field, contact, source-visibility, dense-piece and WALL07–10 suites also pass.
Native import and runtime logs contain no engine errors or leaked resources.
The earlier run `38699658069` also passed; the final commit adds complete BLAS
domain identity, stale-release rejection and allocation-failure cleanup.

| Changed-image event | New visibility queries | Reused visibility results |
| --- | ---: | ---: |
| Explicit cold solve | 161,154 | 0 |
| Same camera, full reprojection | 0 | 161,154 |
| Change source power | 0 | 161,154 |
| Move only key light | 80,577 | 80,577 |
| First 60° camera view | 34,210 | 81,600 |
| Return to known camera | 0 | 161,154 |
| Second independent view, same physical configuration | 0 | 161,154 |

OFF versus WALL10 and direct blocks versus the original search both have
exact RGB error 0 and coverage IoU 1. Across all other image comparisons, the
maximum RGB difference is `1.5397090464830399e-6`, and every coverage IoU is 1.
The saved 8-bit OFF/cold images match exactly. Separate light configurations
invalidate their incompatible channel on the GPU, and returning to the first
configuration restores its image. Zero power, fractional visibility, all eight
slots, metric changes and bank reload/release generations are exercised in the
actual common GPU code against the exhaustive float64 oracle.

For this wall, the additional shared cache is 9,265,420 bytes (772,097 entries).
All three source schedules total 97,632 bytes; the active LOD has 8,418 groups,
535,670 genuine source invocations and 3,082 padding lanes. Control/counters
request another 128 bytes per view. Appearance requests 251,994,824 bytes;
transport requests 1,544,056 bytes. These are RD requested/referenced bytes,
not process PSS or a physical VRAM measurement; shared bytes must not be added
again for each consumer.

On software Vulkan llvmpipe, the recorded visibility pass takes 407.15 ms cold
and 7.87 ms on a known reprojected view, plus 2.12 ms for key/invalidation
passes in that warm event. These are single-event diagnostics with counters
enabled, not a benchmark distribution or Poco FPS. Projection, raster and
appearance work still execute when the camera changes. The cache does not
make a newly visible source free or remove the cost of moving a light.

`LIE-Identidad-0.8.0.apk`: 57,854,901 bytes; SHA-256
`569e33df259787ee09b0d3b493efc1335bf38bdff73ff40bdacb6be0930c7226`.
Package `org.lieengine.wallruntime.v080`, version code 8, minimum SDK 24,
target 36, ARM64 offline. V2/V3 signatures, 16 KiB alignment, actual WALL11
main scene, unchanged bank and all source packets are verified. It installs
beside 0.7. Both new performance switches default ON; diagnostic atomics
default OFF. Godot core remains the official 4.7.2 build.

The inherited scene is static. Geometry edits require rebuilt scene/field
packets and a new cache domain. Fine occluders remain approximate captured
tangent disks, and photographic mortar is not metrically certified. There is
no promise of zero latency, exact mesh visibility, new photographic detail,
native Godot depth participation or measured Poco performance.

Next appearance work remains source-compatible anisotropic filtering and a
separately validated material/emitter extension. A visibility cache cannot
remove source grain by itself; changing view-dependent specular response
would require its own cache policy.
