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
