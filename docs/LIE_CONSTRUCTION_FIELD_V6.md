# Construcción LIE v6: residencia e iluminación compartida

7 de noviembre de 2026. Código de ejecución aceptado: `0e9c6759992d3a61abc231274b8ea7c6fce3247c`, rama `work/lie-construction-field`. Referencia v5 congelada: `963fd4ce3cfe6790422937807ddaec51852be488`.

La esquina fotográfica de 781 instancias ya consume el campo indirecto común de LIE. Con dos luces y dos rebotes, los recursos RenderingDevice contabilizados pasan de **693.17 a 336.98 MiB** respecto al consumidor v5, incluyendo el nuevo campo. El modo de referencia conserva color, cobertura y profundidad bit a bit en las 24 vistas individuales verificadas. Esta entrega es una actualización de datos y código; no es una nueva APK.

## Recursos y conservación de calidad

| Recurso, esquina 960² / reconstrucción interna 1920² | v5, bytes | v6 con campo, bytes |
| --- | ---: | ---: |
| Capturas geométricas y normales residentes | 273 159 680 | 12 335 104 |
| Recursos exclusivos de apariencia | 453 680 304 | 316 911 568 |
| Productor del campo | 0 | 24 105 544 |
| Total contabilizado | 726 839 984 | 353 352 216 |

La reducción es **51.385 %**. Son tamaños de recursos solicitados y registrados por el consumidor/productor, no PSS, RAM total del proceso ni una medición de un teléfono. Se excluyen asignaciones internas del controlador, compiladores/pipelines, modelos de CPU, caché de archivos y copias transitorias de lectura de las pruebas. Los resultados proceden de Vulkan con Mesa llvmpipe; sus tiempos no representan rendimiento móvil.

`lie_capture_pages.gd` carga al iniciar los contratos e índices, y adquiere sólo los intervalos exactos de los LOD usados por los trabajos activos. Cada intervalo tiene SHA-256 geométrico y óptico y conserva sus límites originales. Un búfer compuesto por banco reúne los intervalos activos sin cambiar sus registros. Las concesiones se comparten en el mismo RenderingDevice; otro consumidor de las mismas páginas no vuelve a subirlas. Los cambios de cámara o de luz reutilizan las páginas; cambiar el plan de LOD sustituye la residencia correspondiente.

No se recapturó, cuantizó ni remuestreó el banco. Los originales fotográficos 8K y los bancos inmutables siguen siendo los de v5. La selección de LOD es la misma que usaba v5 en cada prueba. El archivo `pages.json` es un índice, no una captura reducida nueva. Los buffers de proyección bajan de 96 a 80 bytes al retirar un dato derivable sin uso. El consumidor de construcción fusiona sombreado y resolución, evita dos intermediarios RGBA32F y permite reducir la capacidad de trabajo al cambiar de conjunto. El destino final conserva su precisión. Los consumidores anteriores mantienen sus rutas predeterminadas.

## Campo común y radio por código

La integración reutiliza `lie_field_quality_transport.gd`, `lie_area_light_transport.gd` y `lie_surface_light_transport.gd`. No introduce un segundo solucionador exclusivo de muros. Las luminarias se registran en `lie_light_world.gd` y `lie_point_emitter_3d.gd`, con posiciones y potencia RGB lineal relativa.

El adaptador crea superficies finitas a partir de perfiles explícitos de cada maestro, sus seis caras canónicas y las transformaciones reales de sus instancias. Obtiene color medio y rugosidad del material capturado y aplica sus variaciones por instancia. La esquina contiene **4 742 parches, 7 228 conexiones dirigidas y 781 cajas de perfil**. La capacidad común es 8 192 parches y hasta 1 048 576 aristas dispersas, con validación de índices. La textura del campo usa filas de hasta 1 024 elementos; se comprueba el acceso a todos los parches, también fuera de la primera fila.

La opción `energy_radius` usa la política de radio energético ya existente: límite de irradiancia, área de la superficie y reducción por generaciones. El laboratorio parte con esta opción desactivada para conservar la referencia sin recorte. Al activarla usa `radius_max=12`, `radius_decay=.8` e `irradiance_cutoff=.01`. Este radio es una política del transporte secundario y su presupuesto, no la forma geométrica de una lámpara ni una eliminación de la necesidad de visibilidad. No es equivalente a una iluminación físicamente exacta por sí solo. La prueba activa la política, la retira y verifica que vuelve la imagen anterior.

Cada punto reconstruido consulta únicamente parches compatibles de su instancia y cara. No se interpolan materiales o propietarios a través de una abertura. El productor publica irradiancia total y contribuciones directas separadas; el consumidor resta esas contribuciones y añade sólo la parte indirecta difusa. La directa usa el BRDF GGX opaco común. Con cero rebotes, activar la indirecta no añade otra copia de la luz directa.

El puente de apariencia toma recursos GPU del productor actual: no lee resultados en CPU para dibujarlos. Valida propietario, mapeo, identidad de escena, bytes de instancia, dispositivo, época y resolución del productor. Al reemplazar o liberar el productor invalida los descriptores prestados; cada reconstrucción de descriptores usa el recibo del fotograma actual. La puerta cambia rígidamente y reemplaza su campo de pequeño conjunto, conservando las capturas residentes. Cámara y cambios de iluminación no reconstruyen la topología estática.

## Verificación aceptada

[GitHub Actions, ejecución 42368614346](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42368614346): todas las etapas aprobadas sobre el commit de ejecución indicado arriba. Artefacto `13572886857`, SHA-256 `2b1ddcb8bdf1aa59482f92418792cefae349797847216b1e2a60c3de498738e0`.

| Verificación en CI | Resultado |
| --- | ---: |
| Python | 285 ejecutadas; 284 aprobadas, 1 omitida |
| Construcción existente | 49 comprobaciones |
| Componentes existentes | 49 comprobaciones, 24 vistas |
| Campo base GPU | 374 comprobaciones / 15 casos |
| Puente superficial GPU | 404 comprobaciones / 15 casos |
| Calidad del campo GPU | 947 comprobaciones / 29 casos |
| Integración de construcción/campo | 26 comprobaciones |
| Total Vulkan del consumidor actual | 1 849 comprobaciones |
| Rig / sesión de agente / controles del campo | 247 / 25 / 24 comprobaciones |
| Referencia v5 congelada | 24/24 vistas RGBA y profundidad idénticas bit a bit |

La suite comprueba superposición de fuentes, apagar ambas sin energía residual, retirar y reinsertar un emisor, cambiar el radio energético, caché en reposo y movimiento de cámara, mapeos de propietario inválidos, transacciones atómicas y sustitución del productor por apertura, cubierta y puerta. El error máximo de superposición fue `1.86264514923096e-9`; el error relativo máximo de publicación de irradiancia por parche fue `5.82260636981934e-8`.

Una referencia independiente en float64, con dispersión y prueba vectorizada de segmentos contra cajas, compara el campo completo: error absoluto máximo `7.69285890545035e-9`. Usa el mismo contrato aproximado de superficies y visibilidad; verifica el cálculo numérico y los presupuestos del modelo, no equivalencia física con las mallas fuente. El informe `v5-compatibility.json` conserva los hashes de las dos imágenes crudas comparadas en cada vista. Esta identidad exige mismos datos, ajustes, resolución y dispositivo/controlador, con `field_lighting=false`; no es una promesa de identidad entre GPU distintas.

Las capturas comparativas entregadas son nativas de CI, con la misma cámara, fuentes, material y ambiente (`ambient=1`); sólo se conmuta `indirect`. El campo cambia radiancia y mantiene idéntica la profundidad. No se ha generado una ilustración para representar el resultado del motor.

## Límites y correcciones documentadas

- La visibilidad indirecta usa AABB conservadoras de los perfiles. Puede sobreocluir relieves o concavidades. Los enlaces eligen hasta 32 candidatos mutuamente orientados por parche antes de probar visibilidad; el grafo es una aproximación truncada y omite algunos recorridos lejanos.
- La fuente principal conserva la sombra fina común de las capturas. La secundaria usa la prueba de visibilidad del perfil; no se ofrece la misma precisión fina para ambas fuentes.
- La indirecta integrada es difusa. No incluye reflejos indirectos dependientes de vista, vidrio, refracción ni participación automática de mallas o luces nativas de Godot en este campo.
- El trabajo conserva la fidelidad de v5. No recupera el microdetalle ya perdido por su representación ni certifica hiperrealismo. No se añadieron nuevos escaneos completos.
- Durante el desarrollo, recalcular el límite superior del maestro en float64 en lugar de reproducir `Vector3(low) + Vector3(size)` movió ocho píxeles de profundidad. Se corrigió la secuencia float32 y las 24 vistas finales son exactas.
- La primera integración dejó de publicar cambios de luminarias cuando la geometría no variaba; también reconstruía descriptores con un recurso de un productor anterior. Se corrigieron ambas rutas y se verificó retirada/reinserción de fuentes, cambios de conjunto y liberación del productor.
- Elegir vecinos antes de filtrar orientación dejaba sólo 382 conexiones útiles. Ahora se filtra la orientación antes de la selección y el resultado aceptado tiene 7 228 conexiones. Se añadió una regresión de CPU.
- El preparador exige generar las dos referencias comunes antes de crear una escena de pruebas; falla temprano si faltan.

Queda pendiente validar en Android físico el consumo total, latencias, temperatura y estabilidad sostenida. No se ha construido una APK nueva en esta etapa.

## Reproducción

El paquete `LIE_Construccion_Campo_v6.zip` añade índices y campos al banco `LIE_Banco_Construccion_v5.zip` (SHA-256 `3a6d9b713a54f9561337fbbfce1d12c3f4a2b78f6731c062335c22f0b4f828f0`). Verifica identidad y hashes antes de copiar. No duplica los archivos de captura ni los originales 8K. El código debe proceder de la rama publicada, no del código antiguo incluido en v5.

Se comparó cada archivo base de CI con el ZIP v5 entregado. Sólo difiere `banks/brick/asset-profile.json`, una auditoría de transformación fuente que no carga el consumidor nativo: 11 números, con diferencia absoluta máxima `7.105427357601002e-15`. Los registros geométricos/ópticos, contratos, catálogos y recetas coinciden byte por byte. El paquete no reemplaza esa auditoría; sus requisitos registran el SHA real del archivo entregado y ambos hashes para procedencia. El aplicador usa hashes exactos, sin tolerancia numérica.

```bash
git checkout work/lie-construction-field
python -m pip install -r requirements-hq.txt
python /ruta/actualizacion-v6/apply_overlay.py --scene /ruta/LIE_Banco_Construccion_v5/scene
python tools/lie_light_field.py
python tools/lie_field_quality_cases.py
python tools/lie_hq_construction_stage.py --data /ruta/LIE_Banco_Construccion_v5/scene --output /ruta/escena-nueva
```

Con Godot 4.7.2, importar primero la escena preparada mediante `--headless --path /ruta/escena-nueva --editor --import --quit`. Abrir el laboratorio o ejecutar los scripts nativos del workflow con un contexto Vulkan disponible. El script `test_lie_construction_field.gd` escribe el modelo y flujo crudo para volver a ejecutar la referencia float64. La comparación bit a bit necesita preparar por separado el consumidor v5 congelado y volver a producir sus 24 vistas con el mismo dispositivo.

Para regenerar los datos derivados en lugar de aplicar el paquete: ejecutar `tools/lie_capture_page_index.py --root ESCENA` y `tools/lie_construction_field.py --root ESCENA --output ESCENA/fields`. Atribuciones, licencias y procedencia de los originales se conservan en `docs/LIE_HQ_CONSTRUCTION_V5.md` y en el banco v5: ladrillo de Centre-of-Archaeology (CC BY 4.0); materiales de Poly Haven (CC0). Powered by Poly Haven.
