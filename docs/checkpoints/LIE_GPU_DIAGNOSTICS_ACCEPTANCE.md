# LIE 1.8 acceptance

Validated runtime: `039748811a659ce9e3e836db53a0c63abfdf1fbc`.

[Successful native/APK run](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38857488881). All 18 workflows on this runtime head passed.

91 attributed-bank image/depth/work checks, 281 independent compact-view oracle checks, 281 original witness checks, 281 tangent-bound oracle checks, 73 accepted 1.4 checks, 54 prefix-queue checks, 11 actual native-module checks and 16 command/cancellation checks passed. Local CPU rig (247), agent (25) and missing-module fallback also passed.

The paired run retained 54 measured events and 60 predefined warm-ups, with nine events per mode/kind. Six separate work probes retained identical integer counters for all eight metrics. Twelve telemetry boundaries are recorded. The native module loaded; Mali hardware and sensors were explicitly unavailable on this host.

| Event | Original 80 B | Compact 32 B |
|---|---:|---:|
| Camera | 293.808 ms | 290.977 ms |
| Light power | 69.998 ms | 66.595 ms |
| Light position | 174.440 ms | 174.483 ms |

These are **llvmpipe software Vulkan** results and do not predict Mali speed. The moved-light result is effectively tied. Independent runner variation is visible between earlier and final runs; only within-run pairs are compared. Compact shadows remain optional and OFF initially.

APK: `org.lieengine.wallruntime.v180`, `1.8.0-gpu-diagnostics`, 73723342 bytes.
SHA256: `2f8efc414e8c4411212fd7eddc499e1095caa413979d1e7b5aab848070efedd7`.

The signed APK passed archive integrity, original-bank hash, exact per-source 80→32-byte relation, ARM64 ELF, all load-segment alignments of 16384 bytes, native-module/build identity and bundled-license verification. Native dependencies were cross-compiled with NDK r28c; the extension loaded in actual Godot 4.7.2 on the validation host. The APK was not executed on physical Android.

Full evidence: `LIE_GPU_DIAGNOSTICS_NATIVE.json`, `LIE_COMPACT_REFERENCE_NATIVE.json`, `LIE_HARDWARE_PROBE_NATIVE.json` and `LIE_GPU_DIAGNOSTICS_ACCEPTANCE.json` in this directory. Requested appearance allocations total 307543868 bytes, including the additional 16680224-byte immutable view; this is not measured VRAM or PSS.

Earlier integration failures are preserved in the acceptance JSON and GitHub Actions. They came from activating the GDExtension in source-only checkouts before building its library. Installing its descriptor only after successful native compilation fixed those regressions; no failure was relabeled as a pass.

On the phone: open **Comparar GPU**, wait for completion, then **Informe → Copiar**. Timed A/B runs first without hardware sampling; separate hardware intervals follow when permitted. The report retains unsupported/denied counter reasons. Do not infer GPU completion or input-to-photon latency from callback timing.
