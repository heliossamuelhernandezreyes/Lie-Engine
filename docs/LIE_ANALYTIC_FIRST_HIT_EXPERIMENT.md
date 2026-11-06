# LIE — referencia independiente y resolución analítica V5

Fecha: 2026-11-05 (Monterrey). Rama: `research/lie-geometric-sufficiency-audit`.

## Problema comprobado

La muestra V4 de 1,207/1,207/1,211 rayos subestimaba la cantidad de discrepancias. El censo independiente de TODOS los píxeles marcados, más 10,000 extracciones uniformes por pose (semilla 1729), da:

| Pose | Marcados | Errores baseline | Errores V4 | Reparados | Regresiones V4 | Muestra sin marca | Errores sin marca |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0 | 32,391 | 32 | 26 | 22 | 16 | 9,365 | 0 |
| 1 | 32,447 | 30 | 30 | 15 | 15 | 9,401 | 0 |
| 2 | 32,505 | 39 | 25 | 26 | 12 | 9,381 | 0 |

Los 81 errores residuales incluyen 43 regresiones. Los siete errores documentados anteriormente eran solo los de la muestra inicial. No son siete fallos totales de LIE. Evidencia y hashes: [`checkpoints/LIE_V4_ANALYTIC_CENSUS.json`](checkpoints/LIE_V4_ANALYTIC_CENSUS.json). Artefacto original: 13443220998 de la ejecución 42085074488.

## Referencia que no comparte el DDA

`tools/lie_cell_sheet_reference.py` no llama al recorrido de celdas anterior ni al renderizador `regions`. Para cada rayo y proxy:

1. Interseca analíticamente la caja y conserva el contrato de cara de entrada.
2. Construye un rectángulo transversal conservador que contiene el segmento completo del rayo dentro de la caja.
3. Enumera TODAS las celdas ocupadas de ese rectángulo y sus capas, sin avanzar mediante tiempos de cruce DDA.
4. Interseca cada plano y comprueba el soporte semiabierto de su celda.
5. Elige la menor distancia global, conservando un testigo de instancia/cara/celda/capa.

Esta referencia reproduce los siete casos anteriores. Sus siete soportes ganadores también se comprobaron con aritmética racional exacta a partir de los paquetes FP32 originales: [`checkpoints/LIE_V4_SEVEN_RATIONAL_WITNESSES.json`](checkpoints/LIE_V4_SEVEN_RATIONAL_WITNESSES.json). Además coincide con el DDA float64 anterior en 4,096 rayos por pose elegidos con semilla 89 (12,288 comparaciones; cero discrepancias al umbral de 20 micrómetros). Eso aumenta la confianza en la referencia; no demuestra exactitud matemática en empates arbitrariamente pequeños.

## Hipótesis y cambio V5

V4 usa un rayo/recorrido FP32 y comprueba algunos bordes con otro cálculo compensado. Corregir el predicado final no recupera candidatos que el recorrido ya excluyó, ni hace coherentes automáticamente los tiempos de cruce y de impacto.

El shader experimental V5 `tools/shaders/lie_stream_first_hit_analytic.comp.glsl` elimina esos avances DDA. Usa rayos y tiempos globales compensados (dos float32), enumera el rectángulo conservador de candidatos y comprueba soporte semiabierto con productos cruzados antes de arbitrar el primer impacto. La ampliación de una celda es solo del conjunto de búsqueda: NO acepta impactos fuera de sus soportes.

No se ha aumentado la tolerancia de aceptación (20 micrómetros). V4 se conserva sin cambios para comparación. El nuevo shader se selecciona con `lie_stream_first_hit_stage.py --analytic`, en un proyecto temporal separado del renderizador base.

## Aceptación reproducible

`lie-stream-analytic-first-hit.yml` recupera el mismo banco atribuido y fija el checkout original a `0aa2d1db2612902acca4814ec1c1f0f991f921bf`. Ejecuta Godot 4.7.2/Vulkan, conserva el G-buffer base y llama a `lie_stream_exhaustive_compare.py --require-pass` para cada pose. Una discrepancia hace fallar la ejecución: el verde ya no puede confundirse con un informe `strict_gate_passed=false`.

El censo incluye todos los marcados y una muestra uniforme del framebuffer. No es un censo de todo el framebuffer, una prueba de que el detector no omite candidatos, una comparación con la malla original ni una medición móvil. El búfer V5 sigue separado del G-buffer final. La compacción GPU y la publicación de profundidad/normal/material siguen requiriendo validación propia.

## Rechazo de V5 y comprobación completa

[V5 real Vulkan 42164015712](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42164015712), artefacto 13478736147, SHA-256 `4f02b887b9f5ad900e7714ec4c35be7cf6ea9b3f53e0b58805a056156ecb1bdf`: 27/23/25 discrepancias en el censo marcado; 17/14/14 regresiones. Se rechaza V5. El nuevo requisito de aceptación hace fallar correctamente la ejecución.

El censo se amplió localmente al framebuffer COMPLETO de las tres cámaras: **1,555,200 rayos**, con los paquetes auténticos archivados. Cero errores baseline en los 486,009 / 485,953 / 485,895 píxeles sin marca. La combinación hipotética baseline + registros dispersos conserva por tanto 81 errores en V4 y 75 en V5. Esto verifica cobertura del detector en estas tres cámaras, sin garantizar otras escenas, movimientos o candidaturas no rasterizadas. Datos: [`checkpoints/LIE_FULL_FRAME_ANALYTIC_CENSUS.json`](checkpoints/LIE_FULL_FRAME_ANALYTIC_CENSUS.json).

## Variante V6 en evaluación

La enumeración analítica no basta si la aritmética compensada tampoco conserva correctamente sus residuos. V6 sustituye el producto con residuo FMA por una descomposición Dekker de operandos FP32. Un canario Vulkan con entradas leídas desde SSBO (sin plegado de constantes) comprueba que el producto reconstruya un residuo conocido y reporta por separado el resultado FMA del mismo dispositivo. Es una hipótesis instrumental, no un diagnóstico ya confirmado del controlador.

La referencia, el umbral y los datos de aceptación se mantienen. PR de investigación; sin integración en main ni APK nuevo.


## V6: aceptación geométrica alcanzada en las tres cámaras

[Godot 4.7.2 / Vulkan V6, ejecución 42165371062](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42165371062), artefacto **13479121232**, SHA-256 `4d2768cc16fe40387c4e1219745adad980e16badcc060fae87ded2c9e38c54b1`.

| Pose | Errores baseline (fotograma completo) | V4 | V5 | V6 | Regresiones V6 |
|---|---:|---:|---:|---:|---:|
| 0 | 32 | 26 | 27 | **0** | **0** |
| 1 | 30 | 30 | 23 | **0** | **0** |
| 2 | 39 | 25 | 25 | **0** | **0** |

Los 97,343 registros GPU marcados superan la comparación exhaustiva con la referencia independiente. Combinados para evaluación con los píxeles baseline sin marca, coinciden en cobertura, propietario y profundidad con los **1,555,200 rayos** del censo completo al umbral original de 20 micrómetros. También se comprobó la posición 3D: errores máximos 1.580 / 1.439 / 1.688 micrómetros. Los buffers de cámara, proxies, geometría original y máscara son idénticos a V4; no se reutilizó una referencia de otra cámara. Cero estados incompletos y cero escrituras en registros no marcados.

Resultado completo: [`checkpoints/LIE_V6_FULL_FRAME_ACCEPTANCE.json`](checkpoints/LIE_V6_FULL_FRAME_ACCEPTANCE.json). El caso 80→83 y los siete casos archivados quedan resueltos en este censo.

**Incidencia de instrumentación preservada:** el canario auxiliar de esa ejecución conservaba bindings/push constants no utilizados del shader principal, por lo que no despachó. Su salida cero no demuestra nada sobre FMA ni Dekker. Además, `tee` ocultó su código de salida. La aceptación geométrica sí se ejecutó y verificó los registros no nulos contra dos referencias; ese resultado sigue siendo válido. El canario se corrigió con una interfaz mínima, comprobación de bindings y `pipefail`; su verificación queda separada del resultado geométrico. No atribuir el fallo a un controlador solo por este canario inválido.

**Alcance final:** primer impacto experimental aceptado para estas tres cámaras y este banco de celdas. No implica fidelidad a la malla original, corrección de normales/materiales, publicación en el G-buffer, compacción GPU ni rendimiento móvil. El shader conserva lanzamiento completo y resultados densos; no presentar esta prueba como optimización para Android. La investigación permanece en un PR draft.


## Cierre del canario auxiliar: verificado en Vulkan

[Canario independiente 42167117014](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42167117014), commit `d0eff91fb5e3e30cc934ddd13b2459f311430c75`, artefacto **13479282635**: **aprobado** con Godot 4.7.2, Vulkan 1.4.335, llvmpipe LLVM 21.1.8.

Para dos operandos FP32 `0x3f800001` (1 + 2^-23), leídos desde SSBO:

| Método | Parte alta | Residuo | Verificación |
|---|---:|---:|---|
| Producto + FMA | 1.0000002384185791 | **0** | No conserva el residuo requerido |
| Producto Dekker | 1.0000002384185791 | **2^-46 = 1.4210854715202004e-14** | Correcto |

Esto confirma directamente que el producto con residuo FMA no cumple el contrato que necesitaba la aritmética compensada **en este entorno concreto**. No atribuye ese comportamiento a todas las GPUs ni demuestra cómo se comportará Mali. El canario mínimo corregido no usa bindings/push constants del resolutor y `pipefail` hace obligatoria su aprobación. La corrección geométrica V6 y el canario aritmético están verificados por ejecuciones independientes; el shader de resolución es el mismo.

Registro exacto: [`checkpoints/LIE_GPU_ARITHMETIC_CANARY.json`](checkpoints/LIE_GPU_ARITHMETIC_CANARY.json). La repetición completa 42166476975 se quedó preparando dependencias; no sustituye ni invalida los dos resultados completados anteriores.
