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
