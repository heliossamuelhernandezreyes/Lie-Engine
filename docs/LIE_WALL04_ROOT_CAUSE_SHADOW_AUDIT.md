# WALL04 — Diagnóstico reproducible y reparación de iluminación

Fecha: 2026-10-13. Corrección implementada y validada en Godot 4.7.2 Mesa Vulkan. Calidad fotorrealista NO certificada.

## Hallazgo principal

El render original de WALL04 combinaba un bloqueador único de toda la pared con 96 cajas independientes de sombras. Esto cancelaba iluminación directa y transferencia indirecta LIE11 entre ladrillos y oscurecía superficies del propio escaneo. Simultáneamente, algunos puntos escaneados profundos de caras laterales se clasificaban erróneamente como referencia frontal del ladrillo para colocar el mortero.

Ensayo A/B con misma cámara, luz, materiales, banco fuente y 96 ladrillos reales:

| Variante | Píxeles negros opacos |
| --- | ---: |
| Sin corregir oclusión y con sombras activadas | 64415 |
| Solo corrección parcial del bloqueo directo | 52194 |
| Corrección de transferencia directa e indirecta con 96 cajas de sombra reales activadas | 28774 |
| Sin oclusores, diagnóstico (no render final) | 326 |

Reducción comprobada del 55.3% de píxeles negros con las sombras de ladrillos habilitadas. Los píxeles de fuente ladrillo marcados por casi nula iluminación bajaron de 114060 a 47426.

## Código y física

- Herramienta tools/lie_wall04_edge_surface.py: selecciona cara frontal expuesta del escaneo, no puntos profundamente erosionados ni superficies laterales. El mortero conserva 0.8 a 1.3 mm de receso estimado desde el frente local de ambos vecinos.
- gpu_compute/shaders/lie_wall04_transport.glsl: elimina autosombreado por el núcleo opaco global redundante, conservando oclusión directa de otros ladrillos por sus 96 cajas de sombra.
- tools/lie_wall04_factors.py: calcula matriz original-source-grounded de 872×872 transferencias indirectas desde las 96 cajas escaneadas. 48640 pares orientados; 47331 ocluidos; 1309 rutas ópticas admisibles; máximo de energía normalizada por fila 1.0.
- gpu_compute/lie_wall04_transport.gd: inyecta los factores fuente en el cálculo GPU real de LIE11, dos rebotes, sin inventar luces ni sustituir física de absorción.
- tools/lie_wall04_compose.py: recupera y valida SHA del banco de factores binarios.
- Inmutabilidad demostrada: 96 ladrillos XYZ y RGB byte a byte; 872 nodos RGB LIE11; tres LOD; una sola caja invisible de colisión, cero mallas fuente dibujadas. WALL02 y WALL03 históricos sin modificación.

## Evidencia

Run Vulkan validado https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38491223048

Run de publicación SHA-verificada https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38491533389

Source matrix: gpu_compute/assets/lie_wall04/indirect_factors.json y indirect_factors.zlib

Captura real: evidence/LIE-WALL04-CapturedMortar-Neutral.png

Comparaciones: evidence/LIE-WALL04-CapturedMortar-CoreOnly-DIAGNOSTIC.png y evidence/LIE-WALL04-CapturedMortar-NoOccluders-DIAGNOSTIC.png

Control de propietario: evidence/LIE-WALL04-CapturedMortar-CoverageDEBUG.png

Registros: evidence/LIE-WALL04-native-validation.json y evidence/LIE-WALL04-coverage-diagnostic.json

## Limitaciones

Esto NO cierra la aceptación fotorrealista. Persisten 28774 píxeles negros opacos con sombras reales, mezcla de sombras físicas posibles y cobertura incompleta de fuente. Máscaras del mortero fotográfico G1 sin inspección final y escala absoluta del mapa de relieve sin calibración métrica. Los AABB son aproximaciones del ladrillo irregular escaneado. No se ha medido hardware Android. PR #44 continúa como borrador.

Continuar con auditoría de propietario/profundidad y cobertura de juntas, sin pintar vacíos ni añadir polígonos visibles o colisionadores.
## 2026-10-13: Recuperación fotográfica de huecos y calibración de ocho nodos

### Prueba A/B de cobertura sobre el banco idéntico

La ejecución https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38514541166 comprobó el mismo banco fuente SHA-256 f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da, sin alteración de 772097 muestras, de las cuales 240257 son mortero, sin cajas extras ni triángulos visibles.

Las dos variantes del shader WALL04 ahora permiten rellenar solo pequeños intervalos encerrados por píxeles de mortero fotográfico del mismo curso. Exigen profundidad local consistente y posición correspondiente a la junta física. No crean ningún plano ni inventan RGB.

| Métrica, misma captura neutral | Antes | Después |
| --- | ---: | ---: |
| Píxeles ocupados | 355380 | 359594 |
| Píxeles clasificados como mortero fotografiado | 47942 | 49511 |
| Píxeles negros opacos | 27811 | 27705 |

La superficie recuperó 4214 píxeles con la misma fuente y 106 píxeles opacos casi negros menos. Mejora real, pero insuficiente para aceptación visual.

### Experimento negativo: mortero iluminado 17mm por delante de la superficie fuente

En el modelo histórico, los ocho nodos mortero LIE11 864..871 tenían z=0.0563086m, mientras que el banco nuevo fotografiado tiene z cerca de 0.039m, aproximadamente 17mm más atrás. Se creó la herramienta de investigación opt-in tools/lie_wall04_relight.py que reubica únicamente esos ocho códigos a XYZ y normal medidos del banco fotográfico CC0. Conserva idénticos los otros 864 nodos de ladrillo, fuentes de luz, energía, colores, normales, banco de ladrillos y una sola caja invisible; recalcula el transporte indirecto entre los 872 nodos.

La prueba Vulkan https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38514888909 compiló y renderizó, pero empeoró el resultado: 27705 -> 65322 píxeles negros opacos; luminancia media ~89.4 -> ~79.7. La geometría 17mm atrás recibe muy poca luz cuando los 96 envolventes AABB representan sombras de ladrillos macizos. Reubicar nodos por sí solo es físicamente insuficiente y no se puede aprobar.

El workflow principal WALL04 no habilita la recalibración opcional mientras no se corrija al mismo tiempo el acceso real a la luz y el contacto/relieve escaneado. Conservar como referencia funcional la variante anterior, y la nueva herramienta únicamente como evidencia/prototipo. Persisten huecos transparentes, caras inferiores de ladrillo oscuras y falta de revisión G1 de máscaras fotográficas. No se ha medido rendimiento en GPU Android.
