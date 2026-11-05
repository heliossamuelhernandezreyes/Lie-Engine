# LIE — puente reproducible para datos Vulkan reales y rayos Blender originales

**Rama:** `research/lie-geometric-sufficiency-audit` (PR #73, no merge a `main`).  
**Alcance:** pared experimental LIE 2.5 / `work/lie-native-depth`; no confundir con LIE-27 en `main`.  
**Estado:** implementación y pruebas de **formato/contrato**. No se afirma aquí una nueva ejecución Vulkan o Blender, porque el banco atribuido y la malla original no están archivados completos en el repositorio visible. La ejecución registrada en `docs/LIE_NATIVE_DEPTH_RECOVERY.md` pertenece a la rama experimental.

## Qué prueba cada nivel

| Nivel | Dato | Independencia | Estado actual |
|---|---|---|---|
| 1. Fuente | Raycasting Blender contra malla **original autenticada**, cámara igual a la del GPU, coordenadas y dueños mapeados explícitamente | No lee el banco capturado de LIE | Preparado; requiere `.blend` auténtico, transformación verificada y mapa de propietarios |
| 2. Captura LIE | Oráculo float64 de celdas finitas, `tools/lie_native_oracle.py` de la rama experimental; `surface.json`, `depth.bin`, `normal.bin` | No usa el resultado raster del GPU | Preparado; requiere banco atribuido recuperado |
| 3. Consumidor | Volcado `*-native-world.bin` del **RenderingDevice Vulkan real** de `test_lie_native_depth.gd`, con `*-native-views.bin` y `*-native-proxies.bin` | No usa una imagen sintética creada por el analizador | Preparado; requiere ejecución Godot+Vulkan con asset correcto |

El modo `regions` se mantiene únicamente como comparador adicional. No es fuente original.

## Preparación en dos checkouts

Desde el repositorio principal:

```bash
git worktree add ../lie-native-depth work/lie-native-depth
git worktree add ../lie-geometric-audit research/lie-geometric-sufficiency-audit
```

Si la rama ya tiene un worktree, se puede trabajar desde el existente; los comandos anteriores son ejemplos.

En `lie-native-depth`, restaurar los paquetes del banco original al directorio `gpu_compute/captures/liewall06`. Verificar procedencia: SHA-256 de banco **ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340**. Este checksum está documentado, pero no sustituye inspeccionar individualmente los archivos fuente ni asegura que la malla Blender original esté disponible.

Reproducir la prueba Vulkan documentada en esa rama:

```bash
cd ../lie-native-depth
python tools/lie_direct_access_shaders.py
python tools/lie_direct_views_shaders.py
python tools/lie_native_shaders.py
python tools/lie_native_surface.py
python tools/lie_native_stage.py --stage /tmp/lie-native-qa

godot --headless --path /tmp/lie-native-qa --editor --import --quit
godot --path /tmp/lie-native-qa --rendering-driver vulkan --rendering-method mobile \
  --audio-driver Dummy --script res://test_lie_native_depth.gd
```

Esto exige un entorno Vulkan funcional y los binarios del banco. Si falla por faltantes, **NO** reemplazar por `regions`, ejemplos CPU o ceros.

## Etapa A — Captura real vs Vulkan real (sin inventar la fuente)

Desde `lie-geometric-audit`:

```bash
python tools/lie_real_vulkan_triplet.py \
  --captures /tmp/lie-native-qa/native-depth \
  --bank ../lie-native-depth/gpu_compute/captures/liewall06 \
  --experimental-checkout ../lie-native-depth \
  --pose 0 \
  --output /tmp/lie-wall-representation-vulkan.json
```

La selección incluye todos los píxeles con discrepancias de cobertura o propietario entre `regions` y `native`, más una muestra con semilla fija de aciertos y fondo coincidentes. El reporte conserva IDs de píxel y coordenadas, máscara, identidad y profundidad, errores de 20 µm y hashes de los archivos consumidos. **La muestra está sesgada hacia los errores; nunca informar porcentajes como si fuera una muestra aleatoria de toda la pantalla.**

`--all-pixels` permite recorrer los 720×720 rayos para una comparación densa, potencialmente muy costosa en CPU. `--all-details` guarda también los píxeles sin error. Los archivos consumidos son los binarios de Godot, no las PNG.

Sin `--source-npz`, el resultado dice explícitamente `source_status: NOT PROVIDED` y omite `source_to_representation`.

## Etapa B — Raycast de la fuente ORIGINAL en Blender

**Requisito no cubierto por los archivos públicos actuales:** disponer de la verdadera malla fuente en Blender, no un mallado generado desde las mismas celdas de LIE (eso haría circular la validación). Necesitamos revisar y fijar:

- Identidad/hash del `.blend` original y su correspondencia geométrica con la pared capturada.
- La transformación afín **runtime LIE → Blender** (matriz 4×4), con ejes, unidades y escala comprobados. No asumir identidad.
- Un JSON de `object_name → owner_id` donde los IDs realmente equivalgan al identificador que LIE escribió en el canal `world.w`. Si no son equivalentes, debe analizarse profundidad sin usar dueño como prueba.

Preparados esos dos archivos JSON, ejecutar:

```bash
blender --background /ruta/ORIGINAL.blend \
  --python /ruta/lie-geometric-audit/tools/lie_blender_original_raycast.py -- \
  --captures /tmp/lie-native-qa/native-depth \
  --ray-report /tmp/lie-wall-representation-vulkan.json \
  --owner-map /ruta/verified-original-owner-map.json \
  --runtime-to-blender /ruta/verified-runtime-to-blender.json \
  --output /tmp/lie-original-rays.npz
```

Formato `verified-runtime-to-blender.json`:

```json
{"runtime_to_blender":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}
```

**La matriz identidad es solo un ejemplo de formato: NO usarla para el ensayo sin verificar que sea correcta.** El mapa de propietarios es un objeto JSON con nombres de objeto Blender como claves y los IDs nativos como valores, todos verificados. El script falla si impacta un objeto que no tenga mapa.

La fuente exportada lleva SHA-256 de `.blend`, del mapa de IDs, de la matriz y del **paquete de cámara real**. El analizador rechaza cámaras e IDs que no coincidan.

## Etapa C — Triplete fuente vs captura vs Vulkan

```bash
python tools/lie_real_vulkan_triplet.py \
  --captures /tmp/lie-native-qa/native-depth \
  --bank ../lie-native-depth/gpu_compute/captures/liewall06 \
  --experimental-checkout ../lie-native-depth \
  --pose 0 \
  --source-npz /tmp/lie-original-rays.npz \
  --output /tmp/lie-wall-full-triplet.json
```

**Regla de interpretación:**
- fuente ≠ captura, GPU coincide con captura → pérdida/cambio de representación.
- fuente coincide con captura, captura ≠ GPU → error de búsqueda, profundidad o precisión del consumidor.
- fuente ≠ captura **y** captura ≠ GPU → causas superpuestas o compensación; no declarar causa única.
- geometría coincidente, RGB distinto → probar material, normal, sombra y luz en un análisis aparte.

Los `owner_id` solo tienen significado si el mapa de equivalencias es correcto. La primera intersección puede diferir en bordes por precisión numérica, por lo que se conservan tanto errores de cobertura como distancias. Repetir en pose 0 y en las dos poses de yaw ±0.1° (poses 1 y 2), después sombras apagadas/encendidas para RGB.

## Qué ha sido validado por automatización

- Pruebas CPU de extracción/interpretación de paquetes, selección de rayos, fuente ausente, rechazos de cámara y de mapa, y clasificación de discrepancias.
- La prueba de I/O usa datos **sintéticos expresamente etiquetados** para verificar el código; NO constituye una ejecución GPU ni evidencia de la pared.
- El workflow específico de geometría no verifica dispositivos Android, rendimiento, la malla original, Blender, ni fidelidad visual.

## Criterio para decidir arquitectura

No optimizar FPS ni sustituir la representación hasta que el mismo conjunto de rayos establezca qué diferencia existe **fuente→captura** y **captura→GPU**. Si los paquetes faltan, el resultado correcto es **inconcluso con bloqueador de evidencia**, no un diagnóstico inventado.
