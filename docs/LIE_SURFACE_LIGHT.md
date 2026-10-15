# Captured relief and bounded contact shadows — WALL09 / 0.6

This experiment refines **direct** appearance using captured world positions
and geometric normals. It leaves the accepted source-separated field and its
passive bounce budgets intact. It adds no source mesh draws, capture edits,
normal maps, collision proxies or full-frame position atlas.

## Shared implementation

`lie_surface_light_transport.gd` extends the common field. Its stage 6 exports
one stable GPU storage buffer: 16-byte `[surface_count, light_count, 16, 1]`
header, sixteen vec4 light descriptors, then eight surface-count vec4 direct
irradiance channels. Descriptor pairs contain world position/radius and
power divided by the existing emitter cap/distance-squared floor. Direct
irradiance uses the exact field weights, visibility, transmittance and area.
It is published after direct normalization, before bounce accumulation. No
runtime CPU readback supplies appearance. The field owns this RID; consumers
borrow it, and shut down before the producer as in previous laboratories.

`lie_surface_direct.glslinc` provides the common point-source response and
visibility-gated replacement. The wall adapter builds the same convex source
stencil used by the accepted appearance/recovery path. For each light:

* Subtract its exact old direct radiance from the baseline sum.
* Preserve all remaining indirect radiance.
* In detail mode, replace direct radiance by the local captured position and
  normal response, gated by the original finite-patch visibility/transmission.
* In contact-only mode, attenuate the existing direct radiance; never brighten.

This is a local direct-light quadrature refinement. The image-space integral
is **not** certified as a finite-area flux integral. It is not view-dependent
GGX, native Godot lighting, measured photometry or refraction.

`lie_contact_surface.glslinc` traverses at most 2.5 cm toward each light, with
0.3 mm normal bias and 4–32 deterministic samples (default 12). A candidate is
an actual observed source tangent plane bounded by its pixel cell. Its exact
ray intersection must lie inside that cell and the metric traversal interval.
Missing/recovered/off-screen pixels do not cast these additional shadows.
There is a smooth fade in the last quarter of the traversal range.

Consequently, hidden/off-screen occluders and sub-step features may be missed.
The existing finite-patch visibility handles the larger scene scale. These
are screen-space contact shadows, not a world-space visibility solution.

## Cache and allocations

The new appearance stage runs after the original reconstruction/recovery and
before tone mapping/downsampling. Both switches OFF take the accepted path.
Lighting and contact options invalidate shading only. Exposure reruns output
only; an idle image remains cached. Resizing preserves the bank/transport RID.

Recovered pixels retain an extra 32 bytes of source-supported world/normal
data per record: 2,097,152 bytes at the existing 65,536-record capacity. They
can receive contact shadows but never act as contact occluders. Overflow
keeps the old appearance. The transport bridge reserves 272 + 128*N bytes
(111,888 bytes for 872 nodes). Requested buffer sizes are not Android PSS.

`lie_gpu_pass_profile.gd` asynchronously collects RenderingDevice timestamp
deltas. The app/agent exposes per-pass GPU p50/p95 and sample counts. These
compare the same resolution and contact/detail/step settings. Raw rows retain
that configuration and a serial join to geometry/lighting/exposure cache events.
They include cold work; sample counts accompany percentiles. They describe
changed-image solves; idle cached frames do not produce solve
measurements. They are not CPU time, GPU utilization or sustained phone FPS.

## Validation and research

The independent float64 oracle enumerates all bounded observed pixel-plane
intersections; it does not mirror the GPU ray march. Fixtures cover flat and
sloped surfaces, a step, real missing support, reverse light, rigid rotation,
translation and the metric range limit. Real Vulkan fixtures execute the same
common GLSL includes and the direct bridge against the accepted 15-scene field
oracle. Full-wall tests compare OFF to WALL08, contact-only monotonicity,
coverage, cold/cache equivalence, resize, exposure, idle and source residency.

Local checks: five new Python tests, six common-field tests, Godot import,
ten validated UI/agent commands, 247 rig and 25 agent-session checks pass.
The final native run at `a6ad06dd86053eaea4b65fce0a7f0cb6adde08e8`
passes 88 common contact checks, 404 surface-field checks across 15 scenes,
16 full-wall checks and ten surface UI/agent checks. Existing 374 common-field,
27 WALL07, 26 WALL08 and 80 asset-stencil GPU checks also pass.

OFF vs WALL08 maximum RGB error is 1.1920928955e-7, with coverage IoU 1.
Contact-only changes 80,982 RGB channels by at least .001, preserves alpha
exactly and has maximum positive rounding error 1.1920928955e-7. Cold/cache
maximum error is 7.6368451118e-7, with IoU 1. The field remains within
3.3419434452e-6 of its independent float64 reference. These are software
Vulkan results on llvmpipe LLVM 20.1.2; no physical Android performance or
whole-surface continuity is established. The before/after wall images were
inspected; source pinholes/grain remain visible, especially under raking light.

The signed ARM64 APK is 53,354,134 bytes, SHA256
`7e431082ce29597b5c55424ef8ea083d97220db5a0c0beed8793b203bce7945b`.
Its package `org.lieengine.wallruntime.v060` permits side-by-side comparison
with 0.5. V2/V3 signatures, 16 KiB alignment, the embedded source bank and
compiled new controller/profiler were verified. Detailed raw results, hashes
and artifact/run IDs are in `checkpoints/LIE_SURFACE_LIGHT_CHECKPOINT.json`
and `checkpoints/LIE_SURFACE_LIGHT_NATIVE.json`.

Primary research: [Epic contact shadows](https://dev.epicgames.com/documentation/unreal-engine/contact-shadows-in-unreal-engine)
and [Unity HDRP contact shadows](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition%4014.0/manual/Override-Contact-Shadows.html)
use bounded depth-buffer rays for close detail. This supports the scope and
limitations; it is not evidence of this implementation's quality or speed.
Godot 4.7.2 CompositorEffect/RenderingDevice suffice for this stage. No core
fork is needed until native depth/shadow participation or public light-buffer
access establishes a concrete missing engine capability.

## Next measurements on the Poco

The [official X7 Pro specifications](https://www.mi.com/global/product/poco-x7-pro/specs/)
identify Dimensity 8400-Ultra / Mali-G720 with LPDDR5X. The software Vulkan
device used by CI has a different execution and memory system. Its absolute
milliseconds cannot predict this phone's frame rate.

Keep initial shader/cold geometry cost separate from warmed light changes.
Compare the same camera, two emitters and 1080 internal resolution with both
options OFF, contact only, detail only, and both ON; then vary contact steps
and 1440 separately. Record displayed frame rate, per-pass sample count/p50/
p95, and whether frames are cached or actually reconstructed. Sustained
thermal behavior requires a device trace, not a single initial FPS reading.

[Android GPU Inspector](https://developer.android.com/agi/start) provides
system/frame profiling, with support determined by its device validation.
[Arm's Vulkan guidance](https://vulkan.org/user/pages/09.events/vulkanised-2023/vulkanised_2023_getting_started_on_mobile_and_best_practices_for_arm_gpus.pdf)
emphasizes shared memory traffic and thermal constraints on mobile systems.
Use the in-app pass timings to locate the expensive stage, then inspect CPU/
GPU scheduling and memory traffic with supported device counters. Counter
availability must be verified on the actual firmware.

Engineering inference: if the phone is bandwidth limited, reducing redundant
image/buffer traffic is a better first experiment than adding more light
samples. If contact dominates, test fewer/adaptive traversal samples against
the independent visibility fixtures and real-camera coverage acceptance.
Neither inference establishes a speedup before measurement. No FP16 format
conversion, hidden quality reduction or hardware-dependent shortcut ships in
this checkpoint.

## Preserved local failures

* The first float64 rotated fixture landed exactly on a pixel corner; strict
  half-open cell comparisons exposed numerical corner ties. Queries now use
  a declared sub-pixel offset. This is not proof of all real-camera corner ties.
* First staging rejected a truncated local historical WALL04 bank (44,040,192
  bytes, SHA256 25ddcaf3f14ebe193f2dfba505db9d4cf99a858b9f2d42d87f0a456ca08e8a25).
  The original verified 61,767,760-byte source was restored from the previous
  accepted stage and its required f6f7d9f7… hash rechecked. No source recipe or
  accepted bank hash changed. The failed stage was left intact.
