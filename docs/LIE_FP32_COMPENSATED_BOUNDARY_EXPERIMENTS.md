# LIE 2.5 — intersección half-open con aritmética compensada FP32

**Fecha:** 2026-11-05. **Rama:** `research/lie-geometric-sufficiency-audit` (PR #73).  
**Regla:** modificar solamente el shader generado dentro de `/tmp/lie-native-qa` durante los ensayos. **Ninguna de estas variantes está en `main` ni en `work/lie-native-depth`.**

## Diagnóstico que debe resolver

El candidato espurio de propietario 80 se acepta en el píxel (416,434), pose 1, porque la coordenada que en float64 corresponde a **28.999869073** queda en **29.000186920** con el cálculo float32 original: cambia la inclusión en el parche `[29,30)`, aunque el oráculo finito atribuye primer impacto a 83. La diferencia de profundidades entre esos dos impactos es 191.415 mm. Ver [forénsica de bordes](LIE_NATIVE_BOUNDARY_FORENSICS.md).

## V1: compensación activada solo en las fronteras

- Script: `tools/lie_native_compensated_boundary.py`.
- A/B real: [GitHub Actions #42046829562](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42046829562); evidencia `lie-native-compensated-vulkan-evidence` ID **13425112106**.
- Ensayo: aplicar un predicado half-open calculado mediante sumas y productos compensados `float32`/`fma` a los impactos cuya huella float32 queda a menos de **0.002 unidades de celda** del borde del parche. El resto del shader no cambia.
- No se utiliza precisión `double` en GLSL. El ensayo usa Vulkan **por software llvmpipe**, no mide FPS Android ni Mali.
- El shader v1 recibe `plane_coord` ya redondeado como un `float` interpolado plano en la etapa de vértices.

### A/B sobre exactamente la misma unión de rayos conflictivos

| Pose | Base con error | V1 con error | Corregidos por V1 | Errores nuevos por V1 | Pérdidas de cobertura de V1 vs base (720²) |
|---|---:|---:|---:|---:|---:|
| 0 | 8 | 12 | 2 | **6** | 0 |
| 1 | 7 | 5 | 5 | **3** | 1 |
| 2 | 14 | 13 | 5 | **4** | 0 |

Esta unión utiliza TODOS los píxeles con discrepancias reportadas por cada una de las dos ejecuciones, luego vuelve a evaluar ambos buffers reales contra el mismo oráculo independiente. **No es un porcentaje poblacional**: la selección es deliberadamente dirigida.

El caso crítico cambió de 80 → **83**, pero `strict_all_poses_pass=false`. En particular apareció un nuevo píxel faltante, y se detectaron errores de propietario antes ausentes. **V1 queda rechazada como corrección de producción**. Una mejora local no es aceptación geométrica.

## V2: precisión y profundidad original

Se añadió `tools/lie_native_compensated_boundary_v2.py` como siguiente hipótesis, sin alterar v1:

1. Se pasa por atributo plano independiente `lie_native_source_depth=q.depth.x`, evitando reconstruir el plano compensado desde `plane_coord` redondeado.
2. Se declara `precise` en los principales acumuladores aritméticos. El objetivo es impedir que las reordenaciones FP32 del compilador destruyan el término bajo de un par de sumas/productos compensados.
3. El predicado sigue siendo **half-open** y solo se activa a menos de 0.002 celdas; no rellena agujeros, no reconstruye superficies ni habilita mallas tradicionales.
4. Se somete a la misma A/B de tres cámaras y mismos oráculos. Workflow separado: [V2](../.github/workflows/lie-vulkan-compensated-boundary-v2.yml).

**Criterios de aceptación:** 0 nuevos errores en la unión del oráculo; 0 nuevos huecos frente a la versión base en las tres cámaras; resolución correcta del caso 80→83; evidencia de atributos/propietario/profundidad; después medir compatibilidad, consumo y costo físico Android. Si V2 incumple una puerta, continúa siendo un experimento rechazado.

## Limitaciones

- El oráculo contiene las **celdas capturadas**, no una malla Blender original. El triplete completo fuente→representación→GPU sigue bloqueado por la malla y alineación de fuente.
- Las ejecuciones son Vulkan llvmpipe por software. No prueban rendimiento real ni viabilidad en móviles de gama baja.
- Un shader que compile y pase pruebas funcionales puede seguir siendo geométricamente incorrecto. No confundir `CI success` con `strict_all_poses_pass`.


## V2 real — execution success, geometric acceptance FAIL

The V2 experiment ran successfully using Godot 4.7.2 and native Vulkan software rendering (llvmpipe), after installing only the essential Vulkan packages. [GitHub Actions 42050042062](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42050042062) preserved evidence artifact **13427230790** (`lie-native-compensated-v2-minimal-evidence`). A prior runner without a Vulkan ICD fell back to OpenGL and was not considered valid evidence. The separate apt-update workflow stalled in dependency setup. Neither outcome changes the geometric criterion.

V2 passed shader compilation and restored real capture packets. The critical (416,434) pixel changed from owner 80 to owner **83**, but **strict_all_poses_pass=false**.

| Camera pose | Baseline errors on common oracle union | V2 errors | V2 rescued | V2 newly wrong | New coverage misses vs baseline (full 720²) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 8 | 10 | 3 | **5** | 0 |
| 1 | 8 | 6 | 5 | **3** | **2** |
| 2 | 13 | 11 | 7 | **5** | 0 |

The union is generated from the real readback discrepancies of both versions for each pose. It is biased toward problematic pixels and does not estimate a global error rate. Full-frame coverage deltas compare V2 against the original native GPU, not Blender or the capture-cell oracle.

**Conclusion:** V2 is also rejected as a production correction. More accurate isolated boundary predicates do not guarantee consistent arbitration among competing surface candidates across the scene. No release shader, mobile APK, or `main` branch was changed.

## What the real evidence says about a selective resolve architecture

The baseline `regions` and `native` full-frame readbacks disagree on coverage/owner at only **60, 83 and 78 pixels** (poses 0,1,2) of the 518,400-pixel framebuffer: **0.0116%, 0.0160% and 0.0150%**, respectively. The offline flag catches **7/7, 7/7 and 9/11** of the independently diagnosed native errors on the targeted samples. The two unflagged pose-2 errors have a matching owner but incorrect depth.

These are counts from two **already fully computed renderers**. They are **not** proof that flags can be produced cheaply during the native shader pass, or that a sparse resolver will meet any FPS target. The 2 missed depth-only cases show that comparing ownership alone is insufficient.

A reproducible offline feasibility analyzer is `tools/lie_sparse_conflict_feasibility.py`, with regression tests that deliberately demonstrate its depth-only blind spot. Its input is the archived Vulkan A/B evidence ZIP and it does not fabricate ray hits.

### Next experimental design: sparse first-hit conflict resolution

1. **Detect ambiguous pixels without running a second full-frame reference backend.** Candidate sources include conservative patch edges, depth/owner discontinuities, duplicate depth contenders and proxy-overlap intervals. A flag must include same-owner depth errors, not only owner conflicts.
2. **Preserve sufficient candidate information:** pixel, camera/pose hash, proxy/patch/face, owner, depth interval and conservative bounds. The flag must never silently discard an existing valid hit.
3. **Resolve flagged pixels against the actual captured source field**, using a bounded first-hit traversal or reliable candidate hierarchy. If a pixel can have a competing surface not present in the raster candidates, the fallback must be able to discover it; sorting only already-accepted candidates is insufficient.
4. **Correct the primary output coherently**: owner, depth, world XYZ, normal, material and reverse-Z output must come from the same chosen hit. Appearance and shadows are separate tests after geometry is validated.
5. **Prove correctness against the independent float64 cell oracle** at the three failed cameras plus subpixel camera perturbations and disocclusions. Require zero new errors among all altered pixels and no new holes; expand beyond the initial targeted sample.
6. **Then measure GPU cost and thermal behavior** on Android hardware, with a low-end phone target. A software Vulkan experiment cannot guarantee cheap mobile execution.

Keep the source-mesh vs capture proof separate: the authentic original Blender/scan mesh and its validated transforms are still not available in this triplet.
