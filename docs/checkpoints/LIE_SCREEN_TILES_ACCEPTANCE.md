# LIE 1.9 native acceptance

Runtime `550db23479c691495ce73bb18ff45eed3ac57cd4`; [all 19 workflows passed](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38937423752).

- Real attributed bank: 89 checks, including all nine pose/option pairs with zero RGB error, byte-exact depth, lowest-ID owners and all eight integer material channels. The accepted 1.4 startup image also matches exactly.
- CSR prefix on actual Vulkan: 12 checks; controls, cancellation and complete-event reduction: 19. Independent prior suites: compact bank 91, accepted 1.4 73, each of three ray oracles 281 and queue 54. Native report/extension checks also pass.
- Four rotated rounds retain all 144 measured and 160 separately predefined warm-up events. Every mode/kind has twelve complete samples. An independent Python calculation reproduced all event sums and twelve p50/p95 pairs, checked required passes, exact restoration and the four balanced slot orders.

## Software timing result

Device: **llvmpipe (LLVM 20.1.2, 256 bits)**. Same recorded scene within this run. No physical Mali result is claimed.

| Event | Reference p50 | Tiles p50 | Tight p50 | Both p50 |
| --- | ---: | ---: | ---: | ---: |
| Camera | 419.405 ms | 574.963 ms | 419.106 ms | 579.793 ms |
| Power | 157.474 ms | 154.028 ms | 151.166 ms | 150.698 ms |
| Light position | 353.166 ms | 346.016 ms | 263.617 ms | 260.573 ms |

The shared reduction is correct but its software camera total still regresses **37.09%**. It remains experimental and OFF at startup. Its resolve stage is 278.263054 ms in this run; the first pixel-gather stage was 701.555560 ms in another run. That cross-run observation is diagnostic, not a controlled speedup claim. The complete first negative remains in Git.

Tight bounds alone reduce moved-light total **25.36%** in this paired software run. Six separate work probes retain the same receivers, cache/witness hits, unresolved rays and TLAS visits. BLAS visits fall 26.50–31.67% and disk tests 68.01–70.99%. These probes are separate from production timing. Small unrelated power differences do not establish a basis-cache optimization.

## APK and reproducibility

`LIE-Bloques-1.9.0.apk`, 73,782,867 bytes; `org.lieengine.wallruntime.v190`, `1.9.0-screen-tiles`.

SHA256: `4c6801b55fe45991f44e85cd6b7d0b58f8a5d55f4b638ba57331c9a531f7fe51`.

Official Godot 4.7.2 export, alignment, signature/archive checks, ARM64 ELF, 16 KiB load alignment, license presence, immutable bank/view bytes and packet hashes passed. ZIP and APK hashes were independently checked after download. Actual Godot loaded the shader resource extracted from the signed APK: revised resolve SPIR-V is 24,752 bytes; the retained first candidate is 22,536 bytes, with different resource hashes. This confirms the final package contains the revised kernel.

Requested appearance RID bytes are 346,836,612, including 39,292,744 extra tile RID bytes at 1080. Workgroup reductions declare 2,560 shared bytes. Driver backing, process PSS and measured physical VRAM are outside these allocation counters.

Full evidence: `LIE_SCREEN_TILES_NATIVE.json` (losslessly context-factored), `LIE_SCREEN_TILES_ACCEPTANCE.json` (identities and interpretation), and the retained first gather result. No warm-up or measured spike was discarded. Native counters on CI explicitly report no Mali device; the new routes have not run on physical Android.

On the phone use **Comparar GPU → Informe → Copiar**. The benchmark selects all four paths and restores scene/options. A physical comparison is required before enabling the experimental coverage route by default.
