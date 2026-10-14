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