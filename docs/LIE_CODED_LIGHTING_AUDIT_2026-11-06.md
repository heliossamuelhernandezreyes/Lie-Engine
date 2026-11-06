# Auditoría de LIE: iluminación por códigos y radio efectivo

Fecha: 6 de noviembre de 2026. Revisión de arquitectura y código, con pruebas CPU reproducibles. No se modificó el motor de iluminación ni se generó una APK en esta revisión.

## Dictamen

La propuesta original sigue presente: las fuentes inyectan energía, las superficies la reciben, sus códigos materiales determinan qué parte absorben o redistribuyen y el transporte puede limitarse mediante un radio efectivo. La rama móvil más avanzada ya incluye conexiones dispersas, separación por fuente, aproximación direccional y reutilización. Proponer esas cuatro cosas como si no existieran sería una auditoría desactualizada.

Su punto débil actual es la información que pierde la representación: el recorte por contribución individual depende de cómo se divide una superficie; un único momento direccional pierde varios caminos de la misma fuente; la visibilidad indirecta queda fijada al grafo capturado; el campo grueso no contiene toda la respuesta angular que necesita una superficie brillante. Los radios tampoco garantizan por sí solos una reducción de trabajo GPU.

La última APK de vistas mantiene el transporte por códigos para la iluminación indirecta y añade evaluación directa por superficie, BRDF y mapas de sombras. Es una arquitectura híbrida. El control `energy_radius` está **desactivado por defecto** en su cadena de inicialización: conservar el transporte codificado no significa estar usando siempre el recorte energético secundario.

## Alcance y versiones

Se siguió la cadena de fuentes, materiales, transporte, visibilidad, reconstrucción y sombreado. No se revisó cada línea de todos los laboratorios del repositorio.

| Fuente | Versión examinada | Uso en esta auditoría |
|---|---|---|
| Especificación original | `Lie_Engine_Architecture_Specification_v0.1.docx`, 17 de julio | Contrastar la intención original: materiales, propagación, umbrales y separación entre detalle visual y simulación |
| Auditoría anterior | `Auditoria-LIE-Engine-2026-10-14.pdf` | Contexto histórico; no se trasladaron sus carencias automáticamente a las ramas posteriores |
| Rama de reconstrucción V6 | `d115ccc37d3032a31fc246456ee42474ce4279dc` | LIE11/12/13, transporte difuso original y separación del problema de primer impacto |
| Rama móvil experimental | `0aa2d1db2612902acca4814ec1c1f0f991f921bf` | Campo común, CSR, fuentes, integración directa, cachés y óptica direccional |
| Última APK entregada, Vistas 2.5 | `6ee27c4cdd767f1d8d13d7cf03d1139210cd6991` | Comprobar las afirmaciones sobre la APK, sin atribuirle cambios posteriores |

Los archivos del campo común, su referencia Python y el valor inicial de `energy_radius` son iguales entre las dos últimas versiones anteriores. El shader directo sí incorpora en la rama móvil posterior una corrección de profundidad inversa para sombras; no se atribuye esa corrección a la APK 2.5.

## Qué significaba la propuesta original

Un código identifica y describe el estado de una superficie; no sustituye la física mediante el nombre del código. Una lámpara entrega una cantidad de energía. La superficie necesita posición, orientación, área y respuesta material para decidir cuánto recibe y cuánto devuelve. La energía secundaria puede representarse en regiones o nodos y reutilizarse mientras sus dependencias no cambien.

La idea es compatible con separar una captura neutra en escala de grises del color material y de la luz. Sin embargo, el gris no contiene por sí solo el albedo de color, la normal, la rugosidad, la reflectividad ni la transmisión. Esos datos deben conservarse por separado, en espacio lineal y con procedencia conocida. Una sombra capturada dentro del gris tampoco se convierte automáticamente en una textura que pueda recibir cualquier luz.

La especificación original ya distinguía actualización directa frecuente y propagación más lenta por celdas, sondas o grafos, con presupuesto de rebotes, umbral y caché temporal. También advertía que una superficie fuera de cámara puede seguir siendo relevante para iluminar la escena. Esto debe mantenerse al optimizar la visibilidad de la cámara.

## Qué hace realmente el código

| Parte | Estado comprobado | Límite actual |
|---|---|---|
| Inyección de luz | Potencia RGB lineal relativa, distancia, orientación, área y visibilidad | No son lúmenes medidos ni una simulación espectral |
| Respuesta difusa | Reflexión filtrada por gris, tinte y absorción en la ruta original | La calidad depende de la discretización espacial y del modelo material |
| Rebotes | Cada generación consume la frontera anterior y acumula lo recibido | Más rebotes no recuperan direcciones ni visibilidad ya descartadas |
| Radios secundarios | Política de potencia y política basada en umbral de irradiancia | Son aproximaciones de alcance; no una distancia física a la que desaparece la luz |
| Grafo disperso | CSR de entrada y salida; validación de paquetes y pertenencia | La topología de la ruta común es inmutable durante la vida del efecto |
| Dirección | Fronteras separadas por fuente, nodo y generación | Un solo vector por combinación; varios caminos de la misma fuente se fusionan |
| Varias luces | Registro común y hasta ocho canales físicos en el campo examinado | Las luces de área consumen varios canales al muestrearse |
| Luz directa detallada | Posición y normal reconstruidas, BRDF, visibilidad y mapas de sombras | Sombreado directo y campo indirecto tienen distinta resolución y representación |
| Reutilización | Estado residente, invalidación y respuesta directa por fuente | La caché de detalle directo puede crecer con píxeles × fuentes; el campo indirecto no queda congelado por esa caché |
| Vidrio y refracción | Láminas con Fresnel/Beer en laboratorios; experimento óptico LIE35 | No hay transporte refractado completo y general integrado en el campo opaco |
| Reconstrucción V6 | Investigación de primer impacto de cámara | No resuelve automáticamente los trayectos desde las lámparas ni la visibilidad entre nodos |

### Transporte difuso inicial

En `tools/lie_light_transport.py`, la reflectancia inicial es:

`rho = gray_mean × tint_linear × (1 − absorption_code / 1000)`.

La inyección puntual pesa el área receptora, el coseno de incidencia y `1/(4πd²)`, con suavizado cercano y ventana radial. Los factores entre parches aproximan la transferencia por sus centros. Hay normalización conservadora; el modelo original utiliza una corrección global y también dispone de una variante local simétrica. No debe confundirse la conservación resultante con una integración geométrica exacta.

La frontera reflejada se propaga una sola vez por generación. No se vuelve a emitir el total acumulado en cada rebote, lo que evitaría duplicar energía. El resultado visual difuso incluye la reflectancia receptora y la conversión lambertiana por π.

### Campo común posterior

`lie_light_field_transport.gd` y `lie_light_field.glsl` utilizan CSR y mantienen potencia y dirección por fuente. La referencia `tools/lie_light_field.py` compara mediante acumulación independiente en float64, frente al recorrido receptor del shader.

La respuesta opaca combina una parte difusa y una aproximación brillante con Fresnel, metalicidad, rugosidad y absorción. Los lóbulos se limitan para no emitir más de su presupuesto. El vector incidente se obtiene de la suma de direcciones ponderadas por el máximo canal RGB. Esto conserva una dirección dominante, pero pierde la distribución angular y las diferencias de dirección entre colores.

El núcleo no contiene constantes de ladrillos: el adaptador de la pared entrega los paquetes. Eso es un avance real hacia una arquitectura común. Aun así, vincular una nueva lámpara al registro no añade automáticamente un oclusor móvil al grafo indirecto ni integra superficies LIE invisibles en las sombras nativas de Godot.

### Última APK de vistas

La cadena `lie_direct_views_lab.gd` → laboratorios WALL → transporte común llega al campo codificado. `lie_direct_effect.gd` toma sus RID compartidos y `shaders/lie_direct_light.glsl` combina el campo indirecto con iluminación directa detallada.

El shader interpola dentro del grupo material, obtiene el término indirecto y añade por fuente una respuesta BRDF multiplicada por incidencia, una puerta de visibilidad gruesa y la sombra detallada. La suma se filtra y se convierte a la salida visual después. Cambiar de regiones a vistas ajustadas o simples cambia principalmente la recuperación de superficie; no sustituye toda esta cadena de iluminación.

La inicialización heredada de `lie_runtime_android_lab.gd` establece `state["energy_radius"]=false`. Al activarlo se añade `secondary_radii` con modo `irradiance`, máximo 6 m, decaimiento 0.82 y umbral 0.001. Sin activarlo, siguen existiendo lámparas con radio, transporte y absorción; se elimina ese recorte secundario concreto.

## Hallazgos nuevos y reproducibles

Ejecutar desde el repositorio:

```bash
PYTHONPATH=tools python3 tools/lie_coded_lighting_audit.py \
  --field-root /ruta/al/checkout-movil \
  --out docs/checkpoints/LIE_CODED_LIGHTING_AUDIT.json
```

La opción `--field-root` es prescindible para comprobar el transporte original. Para repetir exactamente la comparación con el campo posterior, usar el commit móvil indicado arriba. El JSON contiene hashes de los archivos examinados. Estos son experimentos CPU y un contraejemplo angular local; no son nuevas imágenes GPU ni mediciones del teléfono.

### 1. El recorte individual depende de la subdivisión

Se mantiene una superficie blanca cuadrada de 4 × 4 mm, su material y una superficie receptora a 4 m. Se compara un nodo central con la partición exacta en cuatro cuadrados de 2 × 2 mm, con sus centros separados 2 mm. La potencia puntual, en unidades relativas, se ajusta para que el nodo original reciba aproximadamente 0.1 de flujo y se conserva entre ambas representaciones. La comparación sin recorte cuantifica el error de cuadratura. El tamaño pequeño permite aislar el criterio de alcance de los cambios de integración espacial.

| Representación | Sin radio secundario: flujo indirecto rojo | Con radio secundario: flujo indirecto rojo |
|---|---:|---:|
| Un nodo, referencia original | 0.000198943674889 | 0.000128111112616 |
| Cuatro nodos, referencia original | 0.000198943028323 | 0 |
| Un nodo, campo separado por fuente | 0.000198943665945 | 0.000128111100368 |
| Cuatro nodos, campo separado por fuente | 0.000198943022549 | 0 |

Sin recorte, el error relativo de subdivisión es aproximadamente 0.000325 %. Con la política seleccionada, el alcance original de casi 6 m pasa a casi 3 m por nodo y la contribución desaparece. El comportamiento se reproduce en ambos oráculos, incluido el modo más reciente basado en umbral de irradiancia.

**Interpretación:** cada contribución pequeña puede estar bajo un umbral individual, mientras que su suma importa. No se está creando energía ni está mal reducir el radio de un emisor más débil; falta controlar el error agregado de varios emisores que representan la misma superficie. El ejemplo es una prueba sintética de la política opcional, no una afirmación de que una imagen concreta de la APK haya perdido exactamente esa cantidad.

**Mejora recomendada:** repartir un presupuesto de error por superficie física o agrupación, con cotas conservadoras de la contribución sumada. Al subdividir, repartir también la tolerancia entre los hijos; no aplicar la misma tolerancia absoluta a todos. Mantener el área y la energía totales. Introducir una transición temporal con invalidación correcta para que cambios de LOD no produzcan saltos.

### 2. Separar lámparas no separa todos sus caminos

Dos caminos de la misma fuente llegan con ángulos opuestos de 45° a una superficie especular. El momento medio apunta a la normal. Al reflejar ese momento se obtiene un lóbulo central, aunque los dos caminos originales deberían producir dos lóbulos laterales.

El contraejemplo usa la misma forma de compresión y el mismo exponente angular del campo, rugosidad 0.1 y tres receptores direccionales. Manteniendo los paquetes, los laterales reciben aproximadamente 0.05 cada uno y el centro prácticamente cero. Al comprimir al momento único, el centro recibe 0.1 y los laterales prácticamente cero. **Ambos resultados conservan energía.** La prueba muestra por qué pasividad no implica dirección correcta.

No es una nueva simulación completa de esa escena; es un contraejemplo local de la representación matemática utilizada. La solución existente por fuente resuelve la mezcla entre lámparas, pero no este caso dentro de una misma lámpara.

**Mejora recomendada:** representación angular adaptable. Una distribución difusa amplia puede usar pocos coeficientes; una superficie brillante necesita varios lóbulos o sectores, con potencia RGB propia. Evaluar esa distribución con la normal y la vista del punto final. No multiplicar de forma indiscriminada todos los nodos por decenas de direcciones.

### 3. La política de alcance rompe el escalado lineal

En la misma prueba, una cuarta parte de potencia hace caer el alcance por debajo del receptor y devuelve cero, en vez de un cuarto de la contribución anterior. Es una consecuencia del soporte dependiente de potencia, aunque la ecuación física de transporte con materiales fijos sea lineal respecto a la emisión.

Esto limita qué respuestas pueden reutilizarse mediante simple escalado. **La caché actual de WALL23 es de detalle directo por píxel y fuente; sus métricas indican que el transporte grueso/indirecto se recalcula.** No se encontró que estuviera reutilizando incorrectamente una solución indirecta acotada como si fuera lineal. La restricción debe conservarse si ampliamos esa optimización.

## Otros límites de arquitectura

### Visibilidad y movimiento

El grafo indirecto común está vinculado a geometría y paquetes inmutables. Cambiar posiciones, abrir una puerta o destruir un ladrillo requiere actualizar la visibilidad correspondiente o reemplazar el efecto. Los mapas directos pueden actualizarse por separado; eso no corrige los enlaces indirectos ya almacenados.

Una caja y un plano aproximan un oclusor y pueden cubrir huecos reales. A la inversa, una representación demasiado rala puede dejar pasar luz. Mejorar el primer impacto de cámara con V6 no cambia automáticamente ninguna de esas aproximaciones. Se necesita un contrato compartido de coordenadas, pertenencia y geometría, además de consultas adecuadas desde luces y entre superficies. Compartir el contrato no obliga a usar el algoritmo más caro en cada consulta.

La multiplicación de puerta gruesa y sombra fina en la luz directa merece una prueba específica de huecos: si la puerta gruesa es cero, una consulta fina que ve la lámpara no puede recuperar la contribución. La estructura del código demuestra esa posibilidad; esta auditoría no ha cuantificado su incidencia en imágenes actuales. Debe medirse antes de decidir entre usar la puerta como cota conservadora, sólo como aproximación o eliminarla en superficies con visibilidad fina suficiente.

### Materiales y detalle

El color de una pared es propiedad del material y cambia la luz que devuelve; no debe sumarse como una segunda emisión. Gris, albedo, absorción adicional y energía incidente necesitan un contrato único para evitar aplicar pérdidas dos veces o capturar iluminación dentro del material. Albedo ya medido y una absorción adicional pueden coexistir, pero sus significados deben quedar explícitos.

El transporte en RGB es útil para juegos, pero no conserva un espectro completo. Los códigos no permiten recuperar información que no se capturó. La ruta común examinada es opaca; la refracción general exige conocer por dónde sale el camino y qué ve después, además de aplicar Fresnel y absorción. Añadir un índice de refracción a un registro no basta para obtener vidrio completo o cáusticas.

### Trabajo GPU y memoria

La pared ya tiene 872 nodos y 2618 enlaces no nulos. La prueba de CSR verifica 24,452 bytes frente a 3,041,536 bytes de la matriz densa correspondiente, sin reponderar los enlaces. Es una optimización existente de ese paquete concreto, no una medición de memoria total del motor.

Aunque una ventana radial devuelva cero, las fases del shader todavía recorren enlaces CSR y evalúan pesos para muchos nodos. Reducir el radio no reduce automáticamente la cantidad de hilos despachados ni las lecturas del grafo. El siguiente paso sería una frontera activa y listas de trabajo compactadas o actualizaciones por zonas, después de establecer un criterio de error estable.

La caché directa opcional de WALL23 reserva `128 + render_size² × fuentes × 32` bytes. A 720² con ocho canales son 132,710,528 bytes, aproximadamente 126.56 MiB, sólo en ese buffer. No se afirma que ese tamaño se asigne siempre ni que todos los backends lo usen. La reutilización debe elegirse según el coste y frecuencia de reconstrucción, la memoria disponible y las dependencias. El backend de vistas tiene además su propia política de residencia.

## Comparación con iluminación convencional

La ecuación de transporte describe emisión, incidencia y respuesta material; admite distintas aproximaciones y algoritmos. Ray tracing es una familia de métodos para calcularla, no la definición de toda iluminación convencional [1].

| Aspecto | Rasterizado habitual con sombras | LIE examinado | Path tracing |
|---|---|---|---|
| Superficie visible | Rasterización de geometría | Capturas, vistas o regiones y reconstrucción | Intersección de caminos con geometría |
| Luz directa | Luces que afectan la superficie, BRDF y sombras | Campo compartido y respuesta fina directa en la ruta móvil | Muestreo de luces y BSDF con visibilidad |
| Luz indirecta | Puede usar lightmaps, sondas, volúmenes u otros métodos | Propagación entre parches, por fuente, con aproximación direccional | Estimación de caminos de varios rebotes |
| Radio y códigos | Radios finitos, materiales codificados y datos RGB ya son habituales | Los radios secundarios pueden controlar la propagación entre nodos | Un corte de alcance sería una aproximación adicional |
| Reutilización | También hay precomputación, caché e invalidación | Parte central de la representación y de la ruta móvil | También puede reutilizar muestras o resultados, según el método |
| Compromiso principal | Calidad y coste dependen de la técnica elegida | Pérdida espacial/angular, visibilidad fija y coste de reconstrucción | Ruido, muestras, profundidad y coste por camino |

Godot Forward+ agrupa luces espacialmente; Mobile usa una arquitectura forward adaptada a sus restricciones. No sería correcto comparar LIE únicamente contra un motor que prueba todas las luces contra todos los píxeles sin organización [2].

La conversión de superficies iluminadas en fuentes secundarias tiene antecedentes como Instant Radiosity [3]. Los Light Propagation Volumes propagan una representación espacial y angular compacta y combinan luz indirecta aproximada con sombras directas convencionales [4]. LIE no es idéntico a esos métodos: utiliza parches, pertenencia y capturas propias, pero comparte la familia de decisiones sobre representación y transporte.

Por tanto, **la diferencia principal es cómo LIE representa y actualiza la escena y el campo de luz**, no el uso de números o radios. El valor a demostrar es calidad suficiente con coste total menor para sus escenas y dispositivos objetivo. Esta auditoría no establece novedad científica ni una ventaja universal sobre esos métodos.

## Mejora propuesta, por orden

1. **Contrato común antes de más aproximaciones.** Misma identidad de superficie, sistema de coordenadas, área, normal, material, unidades e invalidación para captura, campo, sombras y sombreado. Integrar las capacidades existentes de la rama móvil; no reimplementar CSR ni separación por fuente en otra ruta paralela.
2. **Radio con presupuesto agregado.** Pruebas de subdivisión, LOD y luz fuera de cámara. Mantener los radios de lámparas y hacer explícita la tolerancia introducida por los secundarios. Registrar cuánto transporte se omite.
3. **Campo angular adaptable.** Conservar varios caminos donde el brillo lo requiera y mantener color por lóbulo. Mantener un modo difuso económico para superficies mates y dispositivos modestos.
4. **Visibilidad dinámica compartida.** Actualizar sólo enlaces/regiones afectados por oclusores o destrucción, con revisiones de geometría y caché. Probar puertas, huecos de mortero, contacto, iluminación rasante y objetos fuera de cámara.
5. **Sombreado final coherente.** Luz directa fina más indirecta de baja frecuencia es una base razonable. Añadir reflejo indirecto dependiente de vista sólo con una representación que lo soporte. Hacer explícita la calidad limitada de vidrio y área finita.
6. **Medir el trabajo que queda.** Tiempos por transporte, reconstrucción, sombras, sombreado y salida; memoria por recurso y total; actualización fría y reutilizada. Añadir fronteras activas, actualización por zona o caché más compacta sólo donde los perfiles indiquen beneficio.

No hace falta modificar el núcleo de Godot para demostrar esos cambios: la cadena ya funciona con RenderingDevice y compositores. Compartir sombras, profundidad y luces nativas sí requiere una interfaz de recursos y vida útil clara. Modificar Godot puede ser una decisión posterior de integración, pero no recupera direcciones ni geometría perdidas en los datos.

## Validación realizada y límites de evidencia

| Comprobación de esta revisión | Resultado |
|---|---|
| Suite Python de la rama V6, con `PYTHONPATH=tools` | 126 pruebas, OK; una omitida |
| Transporte, radios/óptica, proxies, CSR, campo, puente de superficie, área, respuesta de potencia y LIE35 en la rama móvil | 60 pruebas, todas correctas |
| Contraejemplos nuevos | Subdivisión con radio, compresión angular de una fuente y no linealidad del recorte reproducidos |
| Suite Python completa de la rama móvil | 230 pruebas contabilizadas; un error de importación por `trimesh` no instalado y una omitida. No se presenta como suite completa aprobada |
| Nuevas ejecuciones Vulkan o Android en esta auditoría | Ninguna |

Los primeros intentos de ejecutar aisladamente dos pruebas originales fallaron al importar `lie_optics` sin `PYTHONPATH=tools`. Repetir con la ruta correcta y ejecutar la suite completa de la rama V6 pasó. No se clasificó el fallo de importación como un fallo de física.

El checkpoint existente del campo común, validado en el commit `657e077a5a3a7479fe7229907afdf19f4caf3df7`, registra 374 comprobaciones GPU en 15 escenarios, máximo error float64 de `3.34e-6` y pruebas de superposición. Proceden de llvmpipe, no de una GPU física Android. Se revisaron como evidencia histórica de implementación; no se volvieron a ejecutar en esta auditoría ni establecen realismo físico de todas las imágenes.

En la rama V6, los workflows históricos LIE11/LIE13 pueden fallar antes de llegar a Vulkan porque ejecutan todas las pruebas Python antes de instalar NumPy, requerido ahora por investigaciones posteriores. Se verificó ese caso en el job LIE11 `127726909884`, run `42167391735`. Es una deuda de preparación de CI, no una prueba de que el transporte luminoso esté roto. No se alteraron esos workflows en una auditoría previa a la integración.

Para aceptar la siguiente arquitectura faltan pruebas contra una referencia de escena independiente: materiales mates, brillo estrecho, dos caminos de una fuente, luces de área y vidrio con alcance declarado. Comparar con el propio oráculo demuestra implementación del mismo modelo, no que el modelo reproduzca la escena real. Mantener cámara, exposición, materiales y geometría equivalentes, comparar imágenes lineales y medir por separado los cambios de iluminación y de reconstrucción.

Para afirmar una mejora en el Poco X7 Pro harán falta pruebas físicas con la misma escena y calidad, incluyendo memoria, calentamiento y eventos de actualización. Los resultados de primer impacto V6, la pasividad y el Vulkan por software no sustituyen esa medición.

## Archivos principales examinados

- Transporte original: `tools/lie_light_transport.py`, `gpu_compute/lie11_model.gd`, `gpu_compute/lie11_light_effect.gd`, `gpu_compute/shaders/lie11_light_transport.glsl`.
- Captura y óptica: documentación LIE12/LIE13, `gpu_compute/lie13_optics_model.gd`, referencia LIE35 y `docs/LIE_35_DIRECTIONAL_OPTICS.md` de la rama móvil.
- Campo posterior: `tools/lie_light_field.py`, `gpu_compute/lie_light_field_transport.gd`, `gpu_compute/shaders/lie_light_field.glsl`, cargador y adaptadores WALL, `docs/LIE_LIGHT_FIELD.md`.
- Ruta de superficie: `gpu_compute/lie_surface_light_transport.gd`, `gpu_compute/lie_area_light_transport.gd`, `gpu_compute/lie_direct_effect.gd`, `gpu_compute/shaders/lie_direct_light.glsl`, `gpu_compute/lie_direct_views_lab.gd`.
- Caché y controles: `gpu_compute/lie_wall23_response_effect.gd`, `gpu_compute/lie_power_response_policy.gd`, `gpu_compute/lie_runtime_android_lab.gd` y laboratorios heredados.
- Pruebas y checkpoints: familias Python citadas, `docs/checkpoints/LIE_LIGHT_FIELD_CHECKPOINT.json` y registro reproducible `docs/checkpoints/LIE_CODED_LIGHTING_AUDIT.json`.

## Referencias primarias

1. Pharr, Jakob y Humphreys, *Physically Based Rendering*, 4.ª edición, [The Light Transport Equation](https://www.pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/The_Light_Transport_Equation).
2. Godot 4.7, [Internal rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html).
3. Laine et al., 2007, [Incremental Instant Radiosity for Real-Time Indirect Illumination](https://research.nvidia.com/publication/2007-06_incremental-instant-radiosity-real-time-indirect-illumination).
4. Kaplanyan y Dachsbacher, 2010, [Cascaded Light Propagation Volumes for Real-Time Indirect Illumination](https://cg.ivd.kit.edu/publications/p2010/CLPVFRII_Kaplanyan_2010/CLPVFRII_Kaplanyan_2010.pdf).
