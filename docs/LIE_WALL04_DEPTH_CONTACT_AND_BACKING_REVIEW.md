# LIE-WALL04 — Auditoría de profundidad y contacto ladrillo–mortero

Fecha: 13 de octubre de 2026. Implementación REAL publicada en PR #44 (experimental / G1 pendiente).

## Causa encontrada, medida directamente del banco 3D

Una comparación inicial entre el banco XYZ original de los 96 ladrillos y las muestras fotográficas de mortero reveló que la referencia local calculada con el percentil 80 de puntos frontalmente orientados no era equivalente a la superficie del ladrillo realmente cercana al mortero. Aproximadamente **98%** de las muestras fotográficas antiguas quedaban por delante del punto de la cara frontal más cercano en XY en la selección original sin filtro de capa expuesta; diferencia mediana **6.84 mm**. Al filtrar la capa frontal verdaderamente expuesta todavía más de **80%** de muestras infringían esa relación. Este fue un fallo geométrico adicional al error independiente de autosombreado LIE11 ya auditado.

## Correcciones IMPLEMENTADAS

- `tools/lie_wall04_edge_surface.py`: incorpora todas las muestras frontales auténticas por ladrillo (no solo borde y percentil), alineadas con la misma expansión XY visual que usa el shader GPU. El límite de la junta se recorta al **punto real del escaneo frontal más cercano**, y el mortero queda 0.8–1.3mm por detrás. Se excluyen las superficies de la capa trasera/lateral antes de consultar.
- `tools/lie_wall04_bake.py`: mantiene el núcleo fotográfico de mortero de **6 mm**, pero añade **dos filas de muestras de soporte por cada lado** detrás de las aristas astilladas del ladrillo, obtenidas exclusivamente de los recortes PBR fotográficos CC0 reales; no hay plano sintético que complete el fondo. Las muestras de respaldo son 1mm más profundas que las ordinarias, y se codifican en attributes.w para distinguir su procedencia.
- `gpu_compute/shaders/lie_wall04_mortar.glsl` y variante forense: expande solamente en GPU la huella visual original de cada ladrillo hasta un **objetivo de 3mm de separación aparente**, para que la cara escaneada gane el depth test sobre el mortero fotográfico existente. No se reescribe la fuente original ni se agrega ninguna superficie visible de caja.
- `gpu_compute/shaders/lie_wall04_mortar_coverage_diagnostic.glsl`: **verde** = núcleo 6mm fotografiado, **azul** = respaldo fotográfico bajo arista de ladrillo, **rojo** = muestra auténtica de ladrillo casi negra bajo la luz LIE11. No representa el color físico final.
- Regresiones en `tests/test_lie_wall04_mortar_samples.py` y workflow Vulkan nativo validan ABI 80bytes/muestra, identidad de los 96 ladrillos, receso de profundidad, códigos 864..871, y único colisionador invisible.

## Mediciones reales Godot 4.7.2 / Mesa Vulkan (1080×1080)

| Versión con la MISMA cámara y luz | Opaque casi-negro | Píxeles de mortero foto visibles | Píxeles ocupados totales |
| --- | ---: | ---: | ---: |
| Antes de este ajuste, tras corregir LIE11 | 28,774 | 31,793 | 332,210 |
| Contacto con fuente frontal cercana, 6mm sin respaldo | 28,933 | 31,747 | 334,245 |
| Contacto corregido + respaldo fotográfico, 6mm | 26,381 | 49,329 | 347,522 |
| **Último publicado: contacto + respaldo + frente ladrillo más ancho (3mm gap aparente)** | **27,811** | **47,942** | **355,380** |

La última variante prioriza la mayor presencia visual de los ladrillos, que fue lo solicitado; eleva ligeramente la superficie casi negra respecto a la versión 6mm, aunque la reduce respecto del punto inicial. En la vista forense final: núcleo verde **24,237 px**, subsuperficie azul **23,705 px**. Esto es evidencia física de cobertura, no una imagen sintética.

- LOD conjunto final: **772,097 muestras** (antes 633,759), incluidas **240,257 de mortero y subsuperficie fotográfica**, 96 ladrillos originales en tres LOD sin cambios en sus registros.
- Se mantiene **una sola caja invisible de colisión**, 0 triángulos de fuente mostrados y transporte RGB LIE11 872 nodos con 96 AABB de sombras.
- Job Vulkan validado: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38500975230
- Publicación de bancos exactos y captura SHA-verificada: https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38501211365
- Evidencia real: `evidence/LIE-WALL04-CapturedMortar-Neutral.png`, `evidence/LIE-WALL04-CapturedMortar-Raking.png`, `evidence/LIE-WALL04-CapturedMortar-CoverageDEBUG.png`, `evidence/LIE-WALL04-native-validation.json`, `evidence/LIE-WALL04-coverage-diagnostic.json`.

## Estado — limitaciones reales

**No certificar todavía fotorrealismo.** Las franjas oscuras persisten, en especial alrededor de juntas horizontales y regiones donde el escaneo carece de superficies opacas válidas o nodos LIE11 presentan casi cero irradiancia. El nuevo respaldo es una reconstrucción de una textura fotográfica donante: no prueba observación física de mortero del muro histórico bajo esos bordes. El G1 de máscara fotográfica continúa sin aprobación y la altura de desplazamiento absoluta no se ha calibrado. El crecimiento de ~22% de muestras se midió solo en consumo de banco, **sin benchmark de GPU Android**.

Próxima auditoría: propietarios/profundidad de los píxeles vacíos horizontales frente a píxeles opacos realmente en sombra; aumentar la continuidad de la fuente frontal del ladrillo por interpolación local de escaneo ANTES de intentar llenar la pared con color plano. Mantener origen y resultados negativos en GitHub.
