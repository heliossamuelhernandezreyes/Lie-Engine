# LIE 2.5 — geometría predictiva inspirada en streaming de video

**Estado (2026-11-05):** candidato GPU detectado **antes** del \`discard\`, delta de máscaras verificado **sin pérdida** y comparación temporal sobre datos Vulkan reales. **NO** es todavía un corrector de primer impacto en GPU, y **NO** se ha modificado \`main\`. Rama \`research/lie-geometric-sufficiency-audit\`, PR #73.

## Qué se puede aprovechar del streaming (y qué no)

En video, un fotograma I contiene una referencia, los P reutilizan una predicción y codifican residuales. LIE puede aprovechar **el mismo patrón de dependencia/caché** sin convertir la superficie 3D en una textura que se estira:

1. **I-frame geométrico:** banco auténtico de celdas, índices de caras, capas, materiales, límites y transformaciones comprobadas por SHA-256. Cada cámara recibe un paquete de vista. No confundir una imagen aplanada con el banco 3D.
2. **P-frame geométrico:** la vista cambia; las posiciones tridimensionales anteriores sirven para *predecir zonas estables* y priorizar consultas. No garantizan visibilidad ni sustituyen un raycast.
3. **Residual de incertidumbre:** el fragment shader señala peligros **ANTES** de descartar candidatos. Se combinan, cuando convenga, con desoclusiones y residuales de movimiento temporal. Un pixel puede ser geométricamente erróneo aun si su dueño/imagen parecen consistentes entre fotogramas.
4. **Compacción por tiles:** los bits de incertidumbre se agrupan en registros de 8×8 sin pérdidas; no enviar ni resolver de nuevo todos los píxeles si no es necesario. La sobrecarga de atomics y los tiles activos se deben medir en GPU física.
5. **Decodificador geométrico:** un segundo pase consulta el banco capturado y elige el primer impacto entre todos los candidatos relevantes, incluidos los rechazados originalmente. Tiene que escribir propietario, posición, profundidad reverse-Z, normal y material de **un único impacto elegido**.
6. **I-frame de recuperación:** ante cambio de banco, corte brusco de cámara, cambio de topología/transformación, desoclusiones no acotadas o presupuesto desbordado, se fuerza una verificación más amplia. Un P-frame nunca puede truncar píxeles dudosos silenciosamente. Evitar B-frames con latencia extra para respuesta interactiva.

El punto 5 es **diseño pendiente**, no software actualmente integrado. La prueba de codec **no implementa** la reconstrucción de un I-frame de producción ni invalidación completa por cambio de proxies; eso debe añadirse a la integración de runtime.

## Instrumentación Vulkan auténtica antes del descarte

- \`tools/lie_stream_candidate_probe.py\` modifica solo los archivos de **staging temporal** de Godot: \`lie_direct_native.glsl\`, \`lie_direct_renderer.gd\` y \`test_lie_native_depth.gd\`. Los archivos originales de \`work/lie-native-depth\` no se publican ni se reescriben.
- Un SSBO en binding **9** almacena 3 planos de máscara, 16,200 palabras \`uint32\` por plano, total **194,400 bytes** a 720×720. Se inicializa a cero en cada reconstrucción de cámara. Se recupera con \`RenderingDevice.buffer_get_data\`.
- Plano 0: proximidad al soporte del parche finito (\`patch_cells.xy/zw\`), incluyendo el lado que **se va a descartar**.
- Plano 1: proximidad a fronteras enteras de celdas capturadas.
- Plano 2: posible empate de cara de entrada a un proxy, antes de descartar una cara no coincidente.
- \`atomicOr\` marca la ubicación del fragmento **antes del \`discard\` half-open**. La geometría dibujada no se altera. Umbral experimental: **0.005 unidades de celda**; este umbral no es un criterio matemático de certificación.
- Límite crucial: si un candidato no ejecuta el fragment shader porque su rectángulo conservador nunca cubrió ese píxel, **ninguna de estas tres señales puede detectarlo**. El detector no prueba completitud global.

**Ejecución Vulkan reproducida:** [GitHub Actions 42070697177](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42070697177), finalizada con éxito, artefacto **13437200888**, \`lie-stream-vulkan-candidate-risk-evidence\`. Godot 4.7.2, Vulkan 1.4 llvmpipe software, APK recuperado con SHA del banco **ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340**. El pipeline visual de referencia y el instrumentado generaron la **misma imagen geométrica RGBA32F** en las tres cámaras: \`strict_geometry_unchanged=true\`.

### Detección de errores conocidos: todo el conjunto dirigido

| Cámara | Flags generados antes del descarte | Fracción del framebuffer | Errores del oráculo capturados | Tiles 8×8 activos |
| --- | ---: | ---: | ---: | ---: |
| Pose 0, original | **32,391** | **6.2483 %** | **7 / 7** | **2,287 / 8,100** |
| Pose 1, yaw −0.1° | **32,447** | **6.2591 %** | **7 / 7** | **2,275 / 8,100** |
| Pose 2, yaw +0.1° | **32,505** | **6.2703 %** | **11 / 11** | **2,281 / 8,100** |

La muestra de 25 errores es **dirigida y preexistente**: procede de la comparación Vulkan real vs oráculo float64 del **campo capturado**. No es un censo de los 518,400 píxeles, ni demuestra fidelidad a la malla Blender original. Detectar 25/25 **no significa** corregirlos. El píxel crítico **(416,434)** de propietario incorrecto 80, que debería ser 83, queda marcado por planos 0 y 1.

Los planos 0 y 1 fueron **idénticos bit a bit** en las tres vistas de esta pared, por alineación entre rectángulos y cuadrícula del atlas. Esto permite experimentar con un plano único para este banco, pero no autoriza eliminar uno sin nuevos ensayos de otras escenas. Plano 2 añade 29, 49 y 30 píxeles de riesgo respectivamente (alguno puede solaparse).

### Predicción temporal por reproyección

Se usa la posición \`world.xyz\` original y la cámara anterior para comparar al propietario y distancia espacial en la nueva vista (tolerancia experimental 1.5 mm). **No** es una transformación de píxeles RGB ni un renderizado de color.

| Pose predictiva frente a pose 0 | Riesgo temporal solamente | Riesgo candidato ∪ temporal | Nuevos errores del corpus encontrados |
| --- | ---: | ---: | ---: |
| Pose 1 | **60,702** (11.7095 % del cuadro) | **77,545** (14.9585 %) | **0** |
| Pose 2 | **60,922** (11.7519 % del cuadro) | **77,839** (15.0152 %) | **0** |

Unir automáticamente ambas señales **más que duplica** el trabajo sin mejorar la detección de 25 errores conocidos. Por ahora, la señal temporal debe usarse para **control de caché, invalidación, prioridades y desoclusiones**, no como obligación de resolver todos sus residuales. El cálculo temporal retrospectivo tampoco puede detectar vacíos del fotograma nuevo ni superficies estables pero equivocadas.

## Delta de tiles sin pérdida: resultado en CI

- \`tools/lie_stream_delta_tiles.py\` usa un registro \`(uint16 tile_id, uint64 mask8x8)\`, ordenado, sin duplicados, para cada tile activo. Un encabezado incluye versión, índice de fotograma, índice del fotograma de referencia, **SHA-256 exacto del banco** y checksum CRC32. Esta es integridad básica de paquete, no autenticación criptográfica de un emisor.
- El decodificador **rechaza** una fuente distinta, una referencia de fotograma equivocada, un paquete truncado o un checksum incorrecto.
- Si los tiles superan el presupuesto se devuelve \`I_REQUIRED\`, sin enviar una lista parcial.
- \`tools/lie_stream_delta_measure.py\` verificó cada bit contra los tres paquetes GPU auténticos. En una secuencia real, pose 0 sería la referencia I; el archivo delta ilustrativo de pose 0 solo mide el codec.

**Validación independiente:** [GitHub Actions 42071550323](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42071550323), éxito, artefacto **13437216230** \`lie-stream-lossless-tile-delta-evidence\`.

| Pose | Píxeles preservados | Tiles activos | Bytes de delta | Ahorro vs bitset de 64,800 bytes |
| --- | ---: | ---: | ---: | ---: |
| 0 | 32,391 | 2,287 | **22,923** | **64.63 %** |
| 1 | 32,447 | 2,275 | **22,803** | **64.81 %** |
| 2 | 32,505 | 2,281 | **22,863** | **64.72 %** |

\`verified_byte_for_byte_risk_roundtrip=true\` en las tres poses, con presupuesto 2,400 tiles. **Estos bytes son solo señales de revisión**, no geometría, normales, materiales, posiciones ni fotograma de imagen. El conjunto de 2,400 tiles es un presupuesto experimental; en escenas más amplias puede forzar I-frame.

## Qué queda antes de integrar un sistema de video geométrico en LIE

1. **Probar cobertura conservadora antes de rasterizar:** capturar intervalos y parches que podrían impactar un píxel pero no llegaron a producir fragmentos. El actual 25/25 no detecta este fallo estructural.
2. **Compacción en GPU:** trasladar la máscara actual y su scan por tiles a un kernel compute sin readback de CPU; demostrar que el presupuesto se gestiona sin colas perdidas, sincronización incorrecta o cuellos de botella por atomics.
3. **Primer-hit resolver real:** construir una consulta CUDA-free/Vulkan-Godot que lea directamente el banco de celdas, con acceso jerárquico y límites half-open consistentes, con política para distancias equivalentes. Debe poder descubrir candidatos rechazados antes del shading.
4. **Publicación atómica del G-buffer:** world.xyz, propietario, Z, normal y material sincronizados; no basta con reescribir el canal propietario o RGB.
5. **I/P-frame seguro:** políticas de invalidación por SHA de fuente y transformaciones/identidades de instancia, cortes de cámara, cambios de luz/material y carga de assets. El test de codec actual valida SHA de **banco**, no todas estas condiciones.
6. **Conservar rendimiento móvil:** los 48,958,966 triángulos auxiliares de esta ruta correctiva de referencia no son una arquitectura móvil sostenible por sí solos. Medir Mali y equipos modestos antes de prometer 60 FPS.
7. **Prueba de fuente original:** obtener malla Blender original y transformación autenticada para distinguir pérdida de captura de fallo del consumidor.

**Veredicto:** demostración genuina de pre-descarte + mapa de incertidumbre + predicción temporal medible + delta sin pérdida. El siguiente paso es conectar estos tiles al **resolver geométrico GPU**, pero todavía no existe una solución aceptada que garantice visibilidad correcta en LIE de producción.
