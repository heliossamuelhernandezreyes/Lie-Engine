# LIE 2.5 — resolución GPU del primer impacto con máscara tipo streaming

**Rama:** `research/lie-geometric-sufficiency-audit`, PR #73. **Estado:** prototipo de Vulkan compute aislado, en verificación. **No** es un shader aceptado para `main`, Android ni producción.

## Qué se implementó

El flujo experimental sigue el esquema de *streaming geométrico*: (1) cuadro original nativo sobre el banco de celdas; (2) bitset de incertidumbre (pre-descarte) en tres planos; (3) consulta GPU del campo capturado únicamente en píxeles señalados; (4) resultado coherente de primer impacto en un búfer independiente; (5) comparación de resultados con oráculo CPU float64 del mismo banco. El fotograma anterior sirve como señal auxiliar de riesgo, nunca como verdad de visibilidad.

- Shader: `tools/shaders/lie_stream_first_hit.comp.glsl`.
- Integración temporal: `tools/lie_stream_first_hit_stage.py`.
- Comparación frente al oráculo: `tools/lie_stream_first_hit_compare.py`.
- Pruebas estáticas y de contratos: `tests/test_lie_stream_first_hit.py`.
- Ejecución de Godot/Vulkan autentificada: [`.github/workflows/lie-stream-gpu-first-hit.yml`](../.github/workflows/lie-stream-gpu-first-hit.yml).

El nuevo shader hace un *dispatch* completo de **720² hilos**, pero **solo los píxeles marcados** por la máscara ejecutan el recorrido geométrico intensivo. No se implementó todavía compacción GPU para lanzar únicamente un hilo por entrada válida. El coste del escaneo y el lanzamiento completo existe.

Para cada rayo señalado, el compute evalúa las **97 instancias**, interseca cajas, elige la cara de entrada coherente con la captura, recorre las celdas de esa cara hasta una superficie ocupada en cualquiera de las cuatro capas y compara distancias entre instancias. Puede descubrir un candidato descartado por el rasterizador primario, ya que no depende de su lista de fragmentos ganadores. No crea polígonos ni interpola superficies a través de huecos.

## Contrato del registro coherente

El SSBO `lie_first_hit` tiene 64 bytes por píxel de pantalla, repartidos en cuatro `vec4`:

| Offset de floats | Campo | Descripción |
| --- | --- | --- |
| 0–3 | `world` | `xyz` del impacto mundo y `w=owner_id` |
| 4–7 | `normal` | normal mundo y rugosidad |
| 8–11 | `color` | color material y canal alfa |
| 12–15 | `info` | profundidad reverse-Z, estado, número de iteraciones de celda, parámetro de rayo |

Los estados de `info.y` son **0=sin trabajo (fuera de máscara), 1=impacto, 2=sin superficie, 3=recorrido incompleto**. Un límite de iteraciones no se confunde con «vacío» y el validador rechaza cualquier píxel señalado sin estado explícito. En esta fase, **el SSBO no sustituye** `_world`, `_normal`, `_color` ni la textura de profundidad D32 del compositor. No se declara resuelta la integración visual.

El estado, cámara y transformaciones de origen se cotejan con los paquetes de Vulkan y el mismo hash de banco de celdas. No se acepta un shader que cambie la imagen original mientras se le somete a prueba.

## Puertas de evaluación

1. Godot debe compilar el compute y ejecutar Vulkan sin fallback.
2. Toda posición marcada por el bitset debe tener estado definido, sin modificar ninguna posición no marcada.
3. Ninguna posición debe tener estado 3 (desbordamiento) en el ensayo de aceptación.
4. Comparar **los mismos rayos** para el resultado nativo y el compute con el oráculo CPU independiente (todos los errores conocidos más 1,200 rayos marcados por pose con semilla fija). No usar `regions` como referencia geométrica.
5. Exigir simultáneamente **cero errores nuevos, cero errores conocidos restantes y cero discrepancias en el subconjunto medido** para declarar equivalencia de la representación.
6. Mantener separado el pendiente de la malla 3D original (Blender/escaneo). Convergencia con el banco de celdas **no** implica fidelidad respecto a la fuente.
7. Posteriormente: compacción GPU, resultados de material/normal/iluminación en el G-buffer final, pruebas de occlusión/sombra y medición de memoria/temperatura/FPS en Mali real y móviles de gama baja.

**Advertencia:** el algoritmo compute inicial usa aritmética FP32, recorrido de celdas finitas y un criterio de avance conservador. Puede mostrar las mismas ambigüedades de frontera que motivaron la investigación. Por ello, **una ejecución exitosa de CI no implica corrección geométrica**; solo se considerará la comparación contra el oráculo. Ninguna variante de shader queda autorizada para producción por esta documentación.


## Resultados de cuatro iteraciones Vulkan reales (2026-11-05)

Todos los ensayos utilizaron Godot 4.7.2 y Vulkan por software (llvmpipe) sobre el mismo banco original recuperado, las mismas cámaras 720×720 y el mismo corpus dirigido. Cada comparación evalúa el compute y el renderer original **sobre exactamente el mismo conjunto de rayos**: todos los errores archivados más hasta 1,200 muestras marcadas de semilla fija por pose. La muestra no es un censo del framebuffer ni prueba rendimiento móvil.

| Versión | Método de avance | Estados incompletos (poses 0/1/2) | Errores compute contra oráculo (poses 0/1/2) | Regresiones (0/1/2) | (416,434) |
|---|---|---|---|---|---|
| Renderer original (referencia de cada ensayo) | Rasterizado nativo | N/A | **8 / 7 / 12** | N/A | propietario 80, esperado 83 |
| V1 | DDA con t global en FP32 | 9,198 / 9,137 / 9,226 | 361 / 344 / 365 | 356 / 340 / 355 | incompleto |
| V2 | DDA con rayo reubicado al box entry | 3,815 / 4,002 / 3,935 | 145 / 149 / 161 | 143 / 145 / 153 | incompleto |
| V3 | **DDA de índices enteros** y tiempos de cruce | **0 / 0 / 0** | **3 / 4 / 8** | **0 / 0 / 1** | 80 (incorrecto) |
| V4 | DDA entera + predicado half-open FP32 compensado mediante FMA en bordes | **0 / 0 / 0** | **2 / 2 / 3** | **1 / 0 / 0** | **83 (correcto)** |

La versión V4 es la mejor por errores totales y resuelve el impacto de 191.4 mm antes mal atribuido. La prueba de **aceptación estricta falla** en todas las poses; `strict_gate_passed=false`. **El éxito de GitHub Actions verifica ejecución y contratos, NO corrección geométrica completa.**

### Evidencia preservada de cada corrida

- V1, [GitHub Actions 42082004106](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42082004106), artefacto **13440238733**.
- V2, [GitHub Actions 42083025416](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42083025416), artefacto **13442082197**.
- V3, [GitHub Actions 42083985736](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42083985736), artefacto **13441238537**.
- V4, [GitHub Actions 42085074488](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42085074488), artefacto **13443220998**.

Cada artefacto incluye `lie-stream-first-hit-pose{0,1,2}.json`, paquetes de resultados compute RGBA32F de **64 bytes por píxel**, máscaras GPU pre-descarte, readbacks de geometría base y hashes de los datos empleados. El chequeo `exact_same_native_render=true` confirma que añadir el corrector no alteró el renderer original. El hit SSBO para píxeles sin marca permanece cero; los ~32,000 píxeles por pose señalados tienen resultado explícito; **no hubo ningún estado de recorrido incompleto en V3 ni V4**.

### Últimos siete errores de V4: concretos, no esconderlos

La V4 deja **seis errores originales** y añade **una regresión** respecto al renderizador original:

- Pose 0: `(202,312)` sigue eligiendo 557 en lugar de 552. Nuevo error `(132,191)`: conserva propietario 759, pero selecciona una profundidad diferente; el nuevo punto mundo dista del previo ~0.29 mm.
- Pose 1: `(35,237)` elige 651 frente a 653 y `(437,303)` elige 735 frente a 730.
- Pose 2: `(274,389)` elige 351 frente a 349; `(467,420)` sigue vacío aunque el oráculo calcula propietario 106; `(57,493)` elige 222 frente a 218.

El error `(416,434)` sí quedó corregido: el compute publica dueño **83** y profundidad reverse-Z coherente con el impacto elegido, **pero aún no reescribe el G-buffer de producción**.

Los errores residuales combinan candidatos con fronteras casi coincidentes, oclusión por otra instancia y un impacto perdido. No se debe forzar la aceptación mediante una tolerancia mayor ni sustituir el primer impacto por la salida del renderer cuando coincida el propietario sin verificación: eso ocultaría discrepancias de profundidad.

### Próximo trabajo técnico, por orden

1. **Validar primer-hit V4 con un oráculo de traversal independiente** y un conjunto de rayos mayor antes de interpretar el porcentaje de errores de la muestra dirigida; recuperar la malla original Blender para evaluar pérdidas de captura por separado.
2. Auditar por qué los **seis originales restantes** escapan al predicado compensado (en particular los candidatos no rasterizados y el hueco `(467,420)`), y por qué V4 crea un nuevo error de profundidad con el mismo propietario en `(132,191)`.
3. Construir una **compacción real de máscara en GPU**, y usar un SSBO de `N_flags×64` bytes en lugar de `720²×64` (aproximadamente **31.6 MiB**) antes de proponer Android; medir costes del compilador, atlas y recorrido.
4. Solo después diseñar un paso de publicación **atómica y coherente** de world, normal, color y D32 reverse-Z, con invalidación I/P-frame, cambios de cámara/transformaciones y sombras.
5. Medir FPS, GPU time, memoria, temperatura y consumo de batería **en Mali móvil**, no en llvmpipe.

**Estado final del experimento:** V4 demostrado funcional pero geométricamente no aceptado; PR sigue como investigación sin cambios a `main`.
