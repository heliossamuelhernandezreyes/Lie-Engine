# LIE 1.8.1 acceptance

Runtime: `93d3cb304c60ef974e871b62868e1b7725436a18`.
[All 18 workflows passed; native/APK run](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38927358596).

- Production interval ownership: 33 local CPU FIFO checks and the same CTest regression in CI. Control reproduces the old `[1,0,0,3,0,0]` sequence; fresh readers preserve `[1,2,3,4,5,6]`. These are synthetic ownership fixtures, not GPU performance evidence.
- Corroboration, decimal precision, raw-data preservation and copied-report budget: 10 pure Godot checks. Actual extension loading and unsupported-host behavior: 11 checks. Commands/cancellation: 16 checks.
- Actual software Vulkan, attributed bank: 91 image/depth/work checks, 281 independent compact-view oracle checks, 73 accepted 1.4 checks, 281 original witness checks, 281 tangent-bound oracle checks and 54 prefix-queue checks.
- The clean paired run retained 54 measured and 60 predefined warm-up events. Both modes retain identical integer work counts. Original state restored. Rendering/shader equations are unchanged.
- ARM64 NDK build, signature/archive verification, exact bank/view byte relation, native ELF/build identity, 16 KiB load alignment and license checks passed. Native dependencies are only Android system libdl/libm/libc; the static C++ runtime needs no unbundled shared C++ library.

APK: `org.lieengine.wallruntime.v181`, `1.8.1-counter-intervals`.
SHA256: `da9c6f2422a2fcc2c6687c74f5611bc413728a21a118a0eaee34660fa03a608e`.

Full data: `LIE_COUNTER_INTERVALS_NATIVE.json` (complete object with whitespace compacted) and `LIE_COUNTER_INTERVALS_ACCEPTANCE.json` (raw/canonical hashes and build identities). The earlier physical observation, truncation limits and invalid interval attribution remain preserved in `LIE18_PHYSICAL_OBSERVATION.json`.

The corrected interval capture has **not run on physical Android**. The CI host explicitly reports no Mali device. Header counters now distinguish configured access from corroborated intervals; the latter require actual timestamp evidence and active cycles. Hardware counters remain whole-device and their clock is not calibrated to Godot GPU timestamps.

The physical 1.8 test showed no useful compact-view gain. No FPS gain is claimed for this hotfix, and compact shadows remain optional/OFF. On the phone use **Comparar GPU**, then **Informe → Copiar**; the header should report the corroborated interval count, and the compact JSON retains all six hardware blocks and the timing summary.
