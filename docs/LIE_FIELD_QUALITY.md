# Transporte luminoso con presupuesto por área y direcciones separadas

Esta etapa implementa las correcciones derivadas de la auditoría del 6 de
noviembre de 2026. Se apoya en la rama móvil `0aa2d1d`, conserva la ruta anterior
y añade un consumidor de los mismos paquetes capturados. No incorpora V6 ni
modifica geometría, colores, materiales capturados o procedencia del banco.

## Resultado respecto a la APK entregada

| Aspecto | APK Vistas 2.5 (`6ee27c4`) | Laboratorio de esta rama |
|---|---|---|
| Transporte por códigos | Ya existía, incluido en la indirecta | Se conserva y amplía el mismo campo común |
| Radio secundario | Tolerancia individual por nodo | Tolerancia repartida por área; alcance compartido entre sectores |
| Direcciones de una lámpara | Un momento por superficie y rebote | Hasta seis sectores; uno activo para materiales rugosos |
| Oclusores nuevos | Grafo indirecto capturado | Hasta 16 cajas analíticas compartidas con la ruta directa |
| Hueco que la visibilidad gruesa cerraba | La puerta gruesa podía anular la sombra fina | La ruta opaca fina decide sin esa puerta adicional |
| Estado inicial del radio energético | Desactivado | Desactivado, con control visible para comparar |
| Entrega Android | APK existente | Código y laboratorio validados; ninguna APK nueva en esta etapa |

No se cambió el capturador ni se resolvió aquí el primer impacto de cámara.
Los resultados de esta rama corresponden al transporte y a su consumidor fino.

## Relación con iluminación convencional

La propuesta de códigos puede entenderse como una representación compacta del
transporte: fuentes, energía incidente, respuesta del material y conexiones entre
superficies. El radio limita qué contribuciones conserva el cálculo. No introduce
una ley distinta de propagación ni demuestra por sí mismo una ventaja de coste.
La ecuación convencional de transporte también vincula emisión, dispersión,
geometría y visibilidad [1].

Usar superficies iluminadas como fuentes secundarias tiene antecedentes como
Instant Radiosity [2]. LIE emplea sus propios parches, capturas, propietarios y
distribución angular; el parentesco no convierte ambos algoritmos en idénticos.
Su diferencia práctica está en **qué información conserva y cómo la actualiza**.
Aquí se corrigen dos pérdidas concretas: el alcance dependiente de la partición
y la mezcla de caminos de una lámpara. Siguen pendientes una referencia física
de escena independiente y una comparación de coste a calidad equivalente.

## Contrato de superficie

La posición, normal geométrica, área, propietario y paquetes CSR continúan
procediendo del contrato común existente. El nuevo núcleo no conoce cantidades
de ladrillos. `lie_wall_quality_transport.gd` sólo carga y verifica esos paquetes.
Su SHA sigue siendo `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.

`lie_field_quality_transport.gd` amplía el transporte de área existente; conserva
los RID y formatos publicados de irradiancia, materiales y descriptores directos.
Las superficies no se excluyen del campo por estar fuera de cámara. La nueva
política se publica en una instantánea inmutable, mediante el mismo mecanismo
de actualización del transporte. La apariencia también incluye esa política
en su firma de reutilización.

La publicación copia también los arrays anidados del llamador. Modificarlos
después no puede cambiar cajas ni revisiones dentro de la instantánea publicada;
se comprueba tanto en configuración inicial como en actualización de política.

La ruta opaca nueva rechaza láminas ópticas. Los laboratorios anteriores de
vidrio permanecen disponibles. Así, reemplazar la aproximación de sombra gruesa
por visibilidad fina no elimina silenciosamente una transmisión coloreada.

## Radio estable frente a subdivisión

La tolerancia individual anterior era constante. Para el modo nuevo:

`epsilon_i = epsilon_reference * area_i / reference_area`

`radius_i = min(parent_radius * decay, sqrt(outgoing_i / (pi * epsilon_i)), radius_max)`

Se conserva después el multiplicador material de radio. El modo histórico de
potencia también utiliza el mismo reparto de tolerancia. Para flujo proporcional
al área, subdividir una superficie reparte tanto la energía como la tolerancia;
por ello conserva el alcance, salvo diferencias de integración espacial.

Esto es una política de tolerancia local ponderada por área. **No constituye
una cota global de error de imagen.** El área de referencia es explícita, en m²;
no se infiere del número de nodos ni de la superficie visible por cámara.

El caso reproducible divide exactamente un cuadrado de 4 × 4 mm en cuatro
cuadrados de 2 × 2 mm. Conserva la luz, materiales y receptor a 4 m. El modo viejo
elimina la contribución de los cuatro hijos; el nuevo la conserva. La referencia
CPU mide una diferencia relativa de `6.311e-6` entre ambos niveles, atribuible a
la integración por centros y a la ventana radial suave. No se exige identidad
geométrica entre dos cuadraturas distintas.

La primera aserción CPU usó una tolerancia arbitraria de `5e-6`; falló por esa
diferencia medida, de unos `8.1e-10` de flujo absoluto. Se conserva este resultado
negativo. El criterio documentado es `1e-5`, y se mantiene aparte el contraejemplo
histórico de pérdida del 100 %. No se ha modificado el umbral de aceptación GPU
del oráculo anterior.

## Representación angular adaptable

Cada fuente física conserva hasta seis sectores por nodo y generación. Una
superficie rugosa usa un único sector activo; una superficie con rugosidad menor
que `roughness_split` separa direcciones por el eje dominante en el marco tangente
de su normal óptica. Cada sector conserva flujo RGB y su momento direccional.

Los sectores tienen normalización pasiva independiente. Se emite exclusivamente
la frontera anterior, nunca el total acumulado. El radio se obtiene de la energía
saliente agregada del nodo y se comparte entre sus sectores: dividir angularmente
una contribución no introduce otro recorte individual de alcance.

El recorrido se divide en normalización, recepción por sector y reducción del
radio agregado. Los sectores emisores se procesan en pases separados, con
fronteras de dependencia explícitas. Los momentos se normalizan una vez que
han contribuido todos los sectores. La representación GPU son pares `vec4` de
32 bytes; no depende del tamaño de un `struct` propio del controlador.

El contraejemplo nuevo utiliza caminos completos de una misma lámpara: dos
superficies difusas alimentan un nodo metálico sintético, y éste ilumina dos
receptores laterales. Con un único momento aparece una contribución central
espuria. Con sectores, cada lateral recibe aproximadamente `0.0001441394` de flujo
rojo en la segunda generación y el centro queda cerca de cero. El material
metálico es de autoría para la prueba; no se atribuye al capturador fotográfico.

Persisten aproximaciones: caminos dentro del mismo sector se fusionan; la
elección de sector tiene fronteras; una dirección por sector no conserva toda
la distribución espectral-angular. Esta etapa mejora el transporte brillante,
pero la apariencia final indirecta sigue siendo principalmente difusa. No añade
reflejos indirectos completos dependientes de la vista ni cáusticas.

El reparto de radio es por superficie y fuente física. Cambiar el número de
muestras de una lámpara de área puede necesitar además repartir su presupuesto
entre muestras. Aquí se conserva la cuadratura existente de cuatro puntos por
panel, hasta ocho canales físicos, y se verifica su suma; no se afirma invariancia
frente a cualquier nueva subdivisión del emisor.

## Visibilidad dinámica común

El contrato acepta hasta 16 AABB opacos de luz. Se comprueban en la inyección
directa, en las conexiones entre nodos y en el píxel final. Ambos shaders incluyen
la misma función `lie_segment_box`, con el mismo margen relativo de extremos
heredado de las consultas anteriores. No se crea geometría visible de esos
obstáculos: el llamador conserva la responsabilidad de representar y mover el
objeto de escena correspondiente.

Una etapa GPU previa calcula la dirección de llegada y la máscara de visibilidad
de cada conexión. Las guarda y las reutiliza entre fuentes, sectores y rebotes.
Los extremos de las conexiones se compilan una vez a partir de los dos CSR
validados; su codificación se contrasta con un encoder Python independiente.
La misma prueba conserva la transposición y los pesos originales del grafo.

El prefijo mutable de política, áreas y cajas se publica por separado de esa
tabla inmutable. Mover una caja no vuelve a compilar ni subir todas las conexiones.
En el banco de pared se actualizan 14,496 bytes de política; los 1,120,512 bytes
de extremos de conexiones se conservan residentes.

Las publicaciones llevan revisión de visibilidad y comparación con la revisión
esperada. Una revisión antigua o una caja inválida se rechaza antes de cambiar
el estado. Las cotas deben seguir siendo finitas y tener volumen después de
convertirse a float32. Los cambios de visibilidad invalidan transporte y respuesta
directa almacenada; las imágenes de geometría estática y sus mapas de sombra
pueden reutilizarse porque el oclusor nuevo se evalúa analíticamente.

Esto actualiza la máscara de los enlaces candidatos del grafo estático. **Mover
la geometría capturada, abrir nuevos enlaces que faltaban en ese grafo o destruir
su topología sigue requiriendo reconstruir sus paquetes.** No se ha presentado
el registro de cajas como un sustituto general de ese trabajo.

La escena nueva conserva separación por fuente y respuesta direccional activas;
rechaza desactivarlas mediante comandos que dejarían fuera el nuevo contrato.
El modo de comparación de un sector conserva fuentes independientes.

## Sombra fina y aproximación gruesa

La ruta anterior multiplica la iluminación directa por una puerta de visibilidad
gruesa y por el mapa de sombras fino. Una puerta gruesa cero impide recuperar un
hueco aunque la consulta fina encuentre la lámpara.

El consumidor nuevo de material opaco usa el mapa fino y la máscara dinámica
compartida para esa decisión. Conserva la preparación y normalización de fuentes,
BRDF y transporte indirecto. `test_lie_quality_direct_gpu.gd` ejecuta el shader
final real en un píxel controlado: reproduce la pérdida con puerta cero, recupera
el hueco con visibilidad fina, conserva oscuridad si el mapa está cerrado y
bloquea la luz si se introduce una caja dinámica.

La calidad de los mapas finos sigue limitada por su resolución y por la geometría
capturada que los alimenta. Esta corrección no declara físicamente exactas todas
las sombras ni corrige la reconstrucción de primer impacto de cámara.

## Uso y comparación

Abrir `gpu_compute/lie_quality_lab.tscn` en el proyecto principal con Godot 4.7.2.
Conserva la cámara, fuentes y materiales del laboratorio de vistas. El control de
radio energético vuelve a estar visible; mantiene el valor inicial desactivado
para poder comparar la misma condición de la APK previa.

Los botones cambian únicamente el transporte: un sector/tolerancia por nodo o
seis sectores/tolerancia por área. Conservan cualquier revisión de obstáculos
existente. Ambos utilizan el consumidor fino nuevo; esa comparación no equivale
a comparar todos los componentes contra la APK anterior.

La API validada acepta instantáneas de política, por ejemplo:

```json
{"op":"field_policy","options":{"angular_sectors":6,"area_budget":true,"reference_area":1,"roughness_split":0.5,"dynamic_occluders":[],"visibility_revision":0}}
```

Una actualización de obstáculos separada conserva los otros parámetros:

```json
{"op":"light_occluders","boxes":[[[-0.1,-0.1,0.4],[0.1,0.1,0.6]]],"expected_revision":0,"new_revision":1}
```

Para restaurar: publicar `boxes: []`, `expected_revision: 1`, `new_revision: 2`.
Las revisiones son enteros uint32; se aceptan también números JSON integrales,
porque Godot los lee como float. Se rechazan booleanos, fracciones y valores
fuera de rango. Una configuración completa tampoco puede reintroducir una
revisión antigua.

## Presupuesto y límites de rendimiento

Las nuevas reservas tienen capacidad fija de ocho fuentes y seis sectores. Los
dos búferes de frontera y sus límites angulares requieren
`nodes * 8 * 6 * (32 + 32 + 16)` bytes, más política y conexiones. El grafo común
WALL06 usado aquí tiene 872 nodos y 35,016 enlaces: son `3,348,480` bytes de
fronteras/límites, `14,496` de política, `1,120,512` de extremos inmutables y
`560,256` de estado de conexiones. El incremento es `5,043,744` bytes. El
transporte completo con sus puentes solicita `6,587,928` bytes en la ejecución
local; no son memoria total del proceso ni uso de VRAM medido. El grafo antiguo
WALL04 de 2,618 enlaces es otro paquete y no debe usarse para estas cuentas.

Los sectores vacíos omiten evaluaciones de enlaces, pero no se ha implementado
una cola GPU compactada ni una actualización parcial de regiones. Se resuelve
el campo completo cuando cambian sus dependencias. Las reservas no se reducen
al seleccionar un sector; se conservan para evitar cambiar los RID residentes.
Cuando todos los materiales son rugosos se recorre un único sector emisor;
la representación mantiene los otros slots disponibles para cambios de política.

Por tanto no se promete más FPS. Primero se valida la arquitectura y después
hay que medir tiempos por etapa, memoria, calentamiento y estabilidad en el Poco
y en equipos de gama baja. Esta etapa no modifica la versión de la APK existente.

## Reproducción y evidencia

```bash
python -m pip install -r requirements-ci.txt
PYTHONPATH=tools python -m unittest discover -s tests -p 'test_*.py' -q
python tools/lie_field_quality_stage.py --stage /tmp/lie-quality
```

El workflow `lie-field-quality.yml` utiliza Godot 4.7.2, Vulkan Mobile y llvmpipe.
Ejecuta pruebas de comandos, rig, sesión de agente, campo GPU contra float64,
shader final y pared con el banco atribuido. Conserva registros, referencias,
imágenes y resultados numéricos. La pared comprueba cambios de política,
activación del radio, oclusor, restauración, caché fría y retirada de fuentes.

La primera ejecución GPU falló porque los valores integrales de política leídos
desde JSON eran rechazados por exigir tipo `int`; se construía un paquete vacío.
Run `42190765505`, job `127801922030`, artifact `13490275461`, SHA ZIP
`0b8952dcbdd24a576f8694aac528d81103dc4893bf7e8949dd092f14c879e229`.
Se añadió aceptación de números integrales y prueba de ida y vuelta JSON, además
de salida limpia si el ejecutor de pruebas recibe un búfer vacío.

La ejecución siguiente que alcanzó el shader nuevo, run `42191608329` /
job `127804836741`, sufrió un fallo nativo durante su ejecución. No se presenta
como una aceptación numérica. La evidencia final y la causa resuelta se registran
en `checkpoints/LIE_FIELD_QUALITY_CHECKPOINT.json` junto con los negativos.

Los recorridos intermedios con consultas y clasificación dentro del bucle de
recepción fallaron con Mesa 26 / LLVM 21; la misma escena pasó en el kernel v1
y en Mesa 25 / LLVM 19. Reorganizar sólo los temporales, las estructuras o los
pases por sector no lo resolvió. Al separar el estado de conexiones en su propia
etapa, pasaron ambos entornos con las mismas referencias y tolerancias. Esto
documenta una corrección reproducible; no identifica concluyentemente un defecto
particular del compilador.

También se corrigió la liberación de recursos: el padre libera primero el
conjunto de uniformes; después se liberan los búferes adicionales. Hacerlo en
el orden inverso invalidaba automáticamente el conjunto y producía un error al
cerrar la escena, aunque las imágenes fueran correctas.

La preparación aislada usa importación secuencial de recursos, igual que el
proyecto de origen. El intento paralelo que abortó al cerrar el importador se
conserva como fallo de preparación y no como un resultado de física.

### Aceptación final

Código validado: `c15f60ac21777e29f8577d7bfc3df58406359914`.
[Ejecución completa aprobada](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42212206691),
job `127873336046`, Godot 4.7.2, Ubuntu 26.04, Mesa 26.0.8,
llvmpipe LLVM 21.1.8. Se ejecutaron shaders Vulkan reales sobre CPU;
**no se utilizó una GPU física Android**.

| Comprobación | Resultado |
|---|---|
| Suite Python completa | 246 pruebas contabilizadas: 245 aprobadas, 1 omitida |
| Comandos y publicación inmutable | 24 comprobaciones aprobadas |
| Rig y sesión de agente | 247 y 25 comprobaciones aprobadas |
| Campo GPU frente a scatter float64 | 947 comprobaciones, 29 casos; error absoluto máximo `3.34194344520089e-6` |
| Superposición de fuentes del caso angular | Error máximo `9.313225746154785e-10` |
| Restauración del campo tras retirar el oclusor | Diferencia máxima `0` |
| Shader fino final | 8 comprobaciones aprobadas: puerta gruesa, hueco, sombra cerrada y caja dinámica |
| Pared de 96 instancias con banco original | 27 comprobaciones aprobadas |
| Imagen tras ida/vuelta de política, visibilidad y potencia | Diferencia máxima `0` en cada caso |
| Imagen almacenada frente a geometría fría o transporte recién resuelto | Diferencia máxima `0` |
| Imagen con caja que bloquea todos los caminos | RGB máximo `0` |
| Registros: errores de script, liberación y fugas | Ninguno detectado por el escaneo de aceptación |

La única omisión Python corresponde al GLB opcional de LeePerrySmith, adquirido
en su workflow Blender independiente; no omite ninguna prueba nueva de luz.
Las comprobaciones de referencia verifican que GPU y CPU implementan el modelo
declarado. **No sustituyen una referencia física o path traced independiente**,
ni prueban todos los casos de movimiento, LOD o conservación visual temporal.
La prueba de pared de bloqueo total complementa los casos de oclusión selectiva
del núcleo y del shader final; no constituye una suite completa de puertas.

Los resultados originales se conservan en
[field-quality-native.json](checkpoints/lie-field-quality/field-quality-native.json),
[quality-direct-native.json](checkpoints/lie-field-quality/quality-direct-native.json)
y [quality-wall-native.json](checkpoints/lie-field-quality/quality-wall-native.json).
El [checkpoint](checkpoints/LIE_FIELD_QUALITY_CHECKPOINT.json) vincula sus SHA,
los umbrales, recursos y ensayos fallidos anteriores. El ZIP completo es el
artifact `13500305621`, SHA-256
`80f4de48d3c8fd6e93e26e16511d9dd918f895b3254d89a65a7bc01a80b8fe5d`.

### Referencias primarias

1. Pharr, Jakob y Humphreys, *Physically Based Rendering*, 4.ª edición,
   [The Light Transport Equation](https://www.pbr-book.org/4ed/Light_Transport_I_Surface_Reflection/The_Light_Transport_Equation).
2. Laine et al., 2007,
   [Incremental Instant Radiosity for Real-Time Indirect Illumination](https://research.nvidia.com/publication/2007-06_incremental-instant-radiosity-real-time-indirect-illumination).
