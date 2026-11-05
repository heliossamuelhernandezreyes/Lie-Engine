# LIE 2.5 — auditoría forense de borde nativo, propietario 80 frente a 83

**Fecha:** 2026-11-05. **Estado:** diagnóstico reproducido en CPU y con readbacks Vulkan reales; guard experimental **rechazado**. No se modifica `main` ni el shader de producción.  
**PR:** [#73](https://github.com/heliossamuelhernandezreyes/Lie-Engine/pull/73).  
**A/B Godot 4.7.2 + Vulkan llvmpipe:** [Actions 42042892864](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42042892864), éxito de ejecución. Evidencia `lie-real-vulkan-native-triplet-evidence`, artefacto **13422223104** (ZIP con readbacks y reportes). **No son mediciones de Mali o FPS Android.**

## Identidad y geometría del caso extremo

Entrada autenticada: banco `library.bin` SHA-256 `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`; cámaras `1-native-views.bin` y transformaciones `1-native-proxies.bin` del test real. Píxel framebuffer **(416,434)**, pose 1 (yaw −73.00939846°).

- `regions` almacena propietario **83** y posición mundo `(0.629140377, -0.247762203, 0.004330661)`.
- `native` almacena propietario **80** y posición mundo `(0.444266796, -0.225806534, 0.048820555)`.
- Oráculo float64 sobre las **celdas capturadas**: propietario **83** a **2.882374824897 m**.
- Native: propietario **80** a **2.690960059236 m**. Diferencia del primer impacto: **−0.191414765661 m**. Este ejemplo no significa que el motor se desplace geométricamente 191 mm: selecciona un fragmento distinto que está delante.

Se reconstruyó explícitamente el candidato 80 en **instancia de ladrillo 8, cara 4, texel (29,36), capa 3**. Su propietario se obtiene del mismo canal de norma de captura y desplazamiento de instancia que utiliza el fragment shader: `normal.w + p.material.z + 1 = 80`. Es una capa ocupada real; el defecto no requiere inventar un texel.

La celda válida usa intervalos **half-open**: `29 ≤ x < 30` y `36 ≤ y < 37`.

| Operación | Coordenada X del impacto sobre esa celda | ¿Acepta el texel 29? |
|---|---:|---|
| Intersección recalculada en float64, usando los mismos paquetes float32 de entrada | **28.999869073** | No |
| Emulación de las operaciones float32 del shader | **29.000186920** | Sí |

En unidades métricas respecto al borde izquierdo de la celda 29:

- float64: **−0.1431 µm** (fuera).
- float32: **+0.2043 µm** (dentro).
- Tamaño de celda en X: aproximadamente **1.09308 mm**.
- En el origen local de esa instancia, `eye.x ≈ −2.59737 m`, un ULP float32 equivale a **0.2384 µm**.

La ambigüedad numérica a escala de submicrómetros puede determinar qué fragmento gana entre dos ladrillos separados por casi 20 cm. La prueba de desplazamientos subpíxel confirma que el desacuerdo desaparece al desplazar levemente el rayo: no es una deformación uniforme de la escena.

El oráculo independiente de celdas detecta cuatro impactos válidos del ladrillo 9 detrás, encabezados por el propietario **83**; al evaluar exhaustivamente los centros de celda y sus superficies finitas, **no encuentra un impacto válido** en el ladrillo 8 para el píxel exacto con límites half-open. La coincidencia de `regions` con el oráculo en este píxel es evidencia comparativa, no convierte `regions` en verdad de la malla original.

**Interpretación sustentada:** inversión del predicado de pertenencia a una celda por precisión float32 durante la evaluación de intersección, suficiente para explicar por qué el fragmento 80 gana aquí. El shader no mantiene una segunda comprobación robusta del half-open de esa superficie. Esto no demuestra que todos los defectos nativos compartan esa causa.

## Prueba A/B: guardado preventivo de bordes, descartado

Se instrumentó **solamente el shader temporal de pruebas**, después de compilar la rama experimental `work/lie-native-depth`. El único cambio fue un descarte de fragmentos dentro de **0.001 unidades de celda** de los extremos de sus rectángulos. No se ha guardado como shader de producción. El objetivo era comprobar causalidad, no implementar la solución.

Resultado **para el píxel (416,434)**: el guard cambia propietario 80 → **83**, mostrando la superficie correcta del oráculo. Sin embargo, causa nuevas omisiones y sustituciones erróneas.

Comparación sobre **idéntica unión de píxeles conflictivos** en cada cámara: la unión incorpora todos los errores explícitamente reportados por cada ejecución y ambos buffers se reevalúan frente al mismo resultado del oráculo.

| Cámara | Píxeles de unión | Errores base | Errores guard | Corrigió | Errores nuevos |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pose 0 | 223 | 7 | 221 | 2 | **216** |
| Pose 1 | 189 | 7 | 187 | 2 | **182** |
| Pose 2 | 218 | 13 | 213 | 5 | **205** |

Se ha vuelto a comparar la **misma selección** para evitar la trampa de que los informes originales usan subconjuntos diferentes. La pose 2 muestra 13 errores base en esa unión ampliada, frente a 11 errores identificados en su conjunto original.

Medición de cobertura **del framebuffer completo de 720²** al comparar guard contra native base (no contra Blender):

| Pose | Impactos base | Impactos guard | Nuevos píxeles faltantes | Cambios de propietario en solapamiento |
| --- | ---: | ---: | ---: | ---: |
| 0 | 138,811 | 138,792 | 19 | 204 |
| 1 | 138,631 | 138,613 | 18 | 177 |
| 2 | 139,030 | 139,014 | 16 | 194 |

El guard no introduce píxeles extra en esta corrida, pero **elimina impactos existentes** y modifica cientos de propietarios. La muestra de errores de la tabla anterior es **dirigida, no aleatoria ni una tasa de defectos global**. No hay ningún motivo para aceptar este guard como corrección: aunque suprimió algunos falsos oclusores, convirtió muchos impactos legítimos en rechazos u otros propietarios.

## Reproducción

Los datos provienen del artefacto de Actions 13422223104, no de imágenes generadas. Para reconstruir el caso extremo desde el banco verificado y los readbacks reales:

```bash
python tools/lie_native_edge_precision_probe.py \
    --bank /ruta/liewall06 \
    --captures /ruta/native-depth \
    --pose 1 --assert-critical \
    --output /tmp/lie-native-boundary-80-83.json
```

El workflow experimental [`lie-vulkan-attributed-wall.yml`](../.github/workflows/lie-vulkan-attributed-wall.yml) realiza automáticamente la recuperación del banco, una corrida nativa, la prueba forense, un cambio de shader **en un staging temporal**, la segunda corrida A/B y preserva los JSON, paquetes de cámaras y resultados.

La comparación equitativa del mismo conjunto de píxeles se puede repetir sobre el ZIP de Actions:

```bash
python tools/lie_native_guard_union_compare.py \
  --artifact /ruta/github-actions-artifact-13422223104.zip \
  --output /tmp/lie-native-guard-common-union.json
```

## Decisión arquitectónica

1. **Mantener intacto `main` y rechazar la protección `0.001` como arreglo.**
2. Diseñar una prueba de **pertenencia robusta y consistente a parches finitos**, manteniendo el contrato half-open. El cálculo en float32 debe tener un manejo explícito de errores en bordes y no limitarse a truncar resultados ambiguos.
3. Investigar primero una ruta selectiva para **candidatos numéricamente ambiguos**: resolución de celda/píxel con aritmética compensada o consulta de respaldo que preserve primer impacto y propietario. Una implementación con float64 por fragmento no debe suponerse viable en móviles sin verificar soporte/coste. No exigir raycasting completo de cada pixel como solución automática.
4. Validar en las tres cámaras contra el oráculo auténtico, incluyendo **cobertura, propietario y profundidad de todos los píxeles alterados**, no solo el píxel extremo ni la máscara de silueta; añadir desplazamientos subpíxel y coste temporal real.
5. Conservar el pendiente independiente **malla Blender original → captura LIE**. La presente prueba únicamente certifica el defecto relativo a la representación de celdas; no demuestra fidelidad a la fuente 3D original.

**Veredicto:** causa local precisa identificada; corrección ingenua rechazada experimentalmente; parche correcto de primer impacto todavía pendiente. La prueba del shader no se integró ni a `main` ni a `work/lie-native-depth`.
