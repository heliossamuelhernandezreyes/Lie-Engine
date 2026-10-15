# LIE: iluminación por superficies y fuentes independientes

Base: `work/lie-asset-contract` / `ff6a548624559cccdfc98a8ea8b0c55a4300748f`.
El banco aceptado continúa siendo `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
Esta etapa cambia el transporte y su conexión con la escena; conserva las
muestras, colores, instancias, LOD, caja física y reconstrucción de WALL07.

## Problema y comportamiento

El transporte anterior sumaba el flujo de todas las luces y calculaba una sola
dirección incidente ponderada por potencia. Aplicar Fresnel y un lóbulo brillante
a esa dirección puede producir una respuesta distinta a evaluar cada fuente
por separado: las direcciones y los colores perdían su relación.

El campo nuevo conserva un frente de flujo RGB, una dirección incidente y un
radio por **fuente, superficie y generación**. La normalización de los lóbulos
de salida también pertenece a cada fuente. La irradiancia final suma las
contribuciones; continúa usando el mismo consumidor y su caché de geometría.
La luz acumulada nunca se reemite como un frente nuevo. Cada generación emite
exclusivamente el frente recibido en la generación anterior.

Esta representación tiene un límite importante: los caminos procedentes de
una MISMA fuente todavía se reducen a un momento direccional por superficie.
No representa una distribución angular completa ni elimina esa aproximación
en reflejos de orden superior. La respuesta opaca sigue siendo difusa más un
lóbulo brillante aproximado y pasivo, no una BSDF GGX calibrada.

## Código común y adaptador

* `lie_light_field_transport.gd`: entre 1 y 1024 superficies y entre 1 y 8
  fuentes puntuales. Usa el ciclo, caché, timestamps y liberación de RIDs de
  LIE11; el único cambio al padre es un hook de tamaño de búfer inicial.
* `lie_passive_scatter.glslinc`: respuesta opaca compartida. El generador
  `lie_light_field_shader.py` produce el shader real del transporte, sin
  cantidades de ladrillos, recetas de propietario o dimensiones de muro.
* `lie_light_field_loader.gd`: verifica SHA y tamaño de cada paquete fuente.
  El efecto comprueba CSR, rangos, normales, materiales, propietarios y la
  transposición exacta entre los grafos de recepción y normalización.
* `lie_light_registry.gd`: IDs por mundo, ocho slots, copias inmutables,
  baja sin energía residual y rechazo explícito de capacidad excedida.
* `lie_point_emitter_3d.gd` y `lie_light_world.gd`: nodos de escena LIE. Sus
  posiciones se convierten al marco métrico del mundo. El hilo principal
  publica instantáneas; el hilo de render nunca consulta nodos de escena.
  Un mundo acepta traslación/rotación rígida; una escala ambigua se rechaza.
  Los emisores son hijos directos del mundo; IDs duplicados se rechazan antes
  de cambiar el registro. No se crea una segunda luz PBR nativa.
* `lie_wall08_prepare.py` / `lie_wall08_field_transport.gd`: adaptador de la
  pared. Su aritmética de nueve parches por ladrillo queda fuera del núcleo.
  El shell de colisión se excluye del modelo óptico; se usan los mismos
  obstáculos de luz y planos medidos de WALL06, con propietario explícito.

Unidades: metros y potencia RGB lineal relativa. Los parámetros de material
pueden ser de autoría o fuente; no se convierten por sí solos en mediciones
físicas. El radio por umbral es una aproximación de coste que debe compararse
con el transporte sin recorte. No ofrece una cota universal de error visual.

Los frentes, direcciones, acumulación por fuente y normalización tienen
capacidad residente de ocho luces. El trabajo recorre la cantidad de slots publicada; los frentes y fuentes
sin potencia omiten las evaluaciones de sombra y lóbulos que no contribuyen. Añadir una fuente dentro de esa capacidad conserva banco, geometría,
salida y RIDs del transporte. Un slot borrado entrega potencia cero hasta su
reutilización. Un cambio de iluminación vuelve a resolver el campo; el gestor
actual todavía no actualiza subregiones del grafo de forma independiente.

## Integración con Godot revisada

Revisión de Godot **4.7.2-stable**, editor oficial `ed1daf0bf`:

* `servers/rendering/renderer_rd/storage_rd/light_storage.h` mantiene los
  búferes de luces y los atlas de sombras; incluye `update_light_buffers`.
* `.../storage_rd/render_data_rd.h` contiene internamente luces, atlas y datos
  del viewport. Su interfaz pública no entrega esos punteros internos a un
  script de compositor.
* `.../forward_mobile/render_forward_mobile.cpp` actualiza los búferes de luz
  antes del callback de compositor `PRE_OPAQUE`.

El núcleo LIE ya puede ejecutar y encadenar estos cálculos en el RenderingDevice
global con CompositorEffect. **No hay un bloqueo que requiera modificar Godot
para esta etapa**, y no se ha creado un fork ni un módulo C++ sin validar.
Mover este código de control a C++ no reduce por sí mismo el trabajo GPU.

Para compartir luces PBR nativas y sombras habrá que diseñar una interfaz
versionada por viewport/frame para descriptores, matrices, texturas y vida útil.
No conviene interpretar directamente un struct privado de LightStorage ni
retener un RID prestado fuera del frame. Hay además dos requisitos de LIE:
la selección de luces debe cubrir sus superficies y sus caminos indirectos,
y los atlas deben incluir obstáculos virtuales. Las mallas fuente siguen
siendo captura offline. Exponer un atlas nativo no añade automáticamente los
ladrillos virtuales como emisores de sombra ni escribe su profundidad 3D.
La implementación de esa interfaz nativa y la integración con profundidad
3D compartida quedan fuera de esta compilación, pendientes de prueba propia.

Fuentes primarias consultadas:

* [Godot: compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html)
* [Godot: RenderData](https://docs.godotengine.org/en/stable/classes/class_renderdata.html)
* [Código Godot 4.7.2: LightStorage](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/light_storage.h)
* [Código Godot 4.7.2: Mobile](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp)
* [PBRT: reflexión y transmisión](https://pbr-book.org/4ed/Reflection_Models/Specular_Reflection_and_Transmission)
* [DDGI: campos de irradiancia y visibilidad](https://research.nvidia.com/publication/2019-05_dynamic-diffuse-global-illumination-ray-traced-irradiance-fields)
* [AMD: caché de radiancia GI-1.0](https://gpuopen.com/learn/amd-capsaicin-framework-release-gi/)

Estas referencias orientan representación, visibilidad y respuesta óptica.
No son una medición del rendimiento de LIE en Android ni implican que LIE
implemente DDGI/GI-1.0 o necesite su hardware de ray tracing.

## Laboratorio, validación y límites

WALL08 añade una segunda luz fría con intensidad y azimut independientes,
su interruptor y una comparación con la dirección combinada anterior.
Cada fuente tiene un interruptor independiente. La principal conserva los
presets existentes, incluida la luz cálida.
La misma ruta de comandos valida las transacciones de UI y agente.

`lie_light_field.py` es un oráculo float64 independiente que reparte energía
por enlaces mediante scatter/reducciones; el shader real utiliza gather CSR.
Sus 15 escenarios incluyen luces cálida/fría, contribuciones aisladas,
apagado total, absorción, rugosidad, metal opaco de autoría, obstáculo,
propietario explícito, radio, ocho fuentes, traslación y habitación de seis
superficies. El caso de metal comprueba el transporte sintético; no extiende
el capturador fotográfico a materiales metálicos.

`test_lie_light_field_gpu.gd` ejecuta ESE shader en Vulkan y lee cada frente
para comprobar conservación por fuente/generación. `test_lie_wall08_mobile.gd`
compara la imagen con WALL07 usando una luz, verifica el campo completo de
872 superficies frente al oráculo, suma de fuentes, caché/frío, exposición,
IDs, cambio de cantidad de luces, recorte y restauración. Las 13 pruebas
headless de comandos comprueban apagado, restauración y transacciones inválidas
antes de la comparación de imágenes. Se mantienen las
aceptaciones previas de WALL07 y del núcleo de interpolación de assets.

Límites vigentes: no refracción de caminos, cáusticas, transmisión por volumen,
luces de área/direccionales, campo angular completo, sombras a resolución
fotográfica ni brillos especulares dependientes de la cámara en la apariencia.
La visibilidad indirecta continúa siendo el grafo capturado; la escena no
adquiere obstáculos móviles arbitrarios por registrar una luz. No se han
eliminado los huecos de cobertura pendientes. Un shader correcto y una
compilación Android no certifican FPS, consumo ni temperatura del Poco.

Resultados y negativos: `checkpoints/LIE_LIGHT_FIELD_CHECKPOINT.json`.

## Resultado de la compilación 0.5

Código validado: `657e077a5a3a7479fe7229907afdf19f4caf3df7`.
[Run 38667463039](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38667463039):
**374 comprobaciones GPU en 15 escenarios y 26 comprobaciones de pared**,
además de 27 de WALL07, 80 consultas del núcleo común de interpolación,
27 contratos de campo/escena y 13 de comandos. Importación y ejecución sin
errores ni fugas de recursos reportadas. Dispositivo: llvmpipe LLVM 20.1.2, Vulkan Mobile.

Error máximo del campo pequeño frente a float64: **3.34e-6**; suma de fuentes:
**1.66e-7**. En la pared completa: **1.00e-8** frente a float64 y **1.86e-9**
en suma de fuentes. Una luz frente a WALL07: IoU 1, máximo RGB **1.19e-7**;
caché frente a reconstrucción fría: IoU 1, máximo **1.79e-7**.

El defecto de dirección combinada se reproduce en el escenario brillante
sintético: diferencia máxima **0.01112** en flujo relativo. En el ladrillo
rugoso de la pared, el cambio aislado de separación es pequeño: máximo de
imagen **0.00217**, MAE **5.70e-7**. No se presenta esa corrección como una
transformación visual completa de la pared. La segunda luz sí añade su
contribución independiente y se puede apagar junto con la principal.

Búferes solicitados por el transporte: **1,432,168 bytes**; apariencia:
**228,578,212 bytes**. Son contabilidades de RIDs, no PSS ni uso total de RAM.
La captura de referencia y los colores conservan su SHA anterior.

APK **LIE Luz 0.5**, `org.lieengine.wallruntime.v050`, ARM64,
**53,122,952 bytes**, SHA256
`033cac4e1ea278babcd1b0bcabd9114cce01c8bb71ea3515d87a5e7c575c2571`.
Se instala junto a 0.4. La exportación verificó firma, alineación de 16 KiB,
manifiesto, banco y todos los paquetes del campo. No hay una nueva medición
de FPS, temperatura o memoria de proceso en un teléfono físico.

Evidencia completa: `checkpoints/LIE_LIGHT_FIELD_NATIVE.json`; el checkpoint
conserva también el primer resultado negativo y su causa comprobada.

Los **19 workflows de PR** terminaron aprobados para ese mismo commit de código.
El commit posterior registra únicamente documentación y evidencia.
