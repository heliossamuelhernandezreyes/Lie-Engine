# LIE-15 — Robot de Arcont y cámara de percepción

El laboratorio `gpu_compute/lie15_lab.tscn` construye un robot de quince piezas a partir de **un maestro real**: `box-small.glb` de Factory Kit 3.0, creado por Kenney y catalogado en Arcont como `ARC-ASSET-KENNEY-696C714A33FF63A1`.

## Procedencia y preparación

`gpu_compute/assets/lie15/provenance.json` identifica el registro de Arcont, el commit consultado, la página oficial, el miembro del ZIP y los SHA-256 de archivo, modelo y paleta. El registro y la licencia CC0 están incluidos. Los pequeños archivos fuente se preservan como Base64 para una preparación reproducible sin depender de una URL cambiante. No son un cubo generado que se presenta como un asset externo.

Blender centra la pieza y normaliza su caja a una unidad por eje. Convierte la paleta original a gris y conserva la geometría y sus detalles. La cámara de captura se mueve alrededor de la pieza fija: 12 azimuts × 5 elevaciones, 128 × 128 píxeles por vista. Cada dirección produce **un albedo gris, una normal y una profundidad**. No se capturan variaciones de ángulo de luz.

El empaquetador reconstruye muestras XYZ en espacio del objeto. Rechaza bordes mezclados alejados más de 12 mm de la malla original durante la preparación; no consulta esa malla en la cámara Lie. Seis nodos aproximan el transporte difuso de la pieza y su caja sirve para percepción, colisión y sombras aproximadas.

## Robot, escala y cámara

Un único buffer inmutable se comparte entre torso, cabeza, pelvis, dos brazos de dos segmentos, dos piernas de tres segmentos y dos ojos. Cada pieza tiene una transformación independiente. Las proporciones se fijan por escala local positiva y las articulaciones cambian solamente rotación/posición. Las normales usan la **inversa transpuesta**, necesaria con esas proporciones; no se asume que una base escalada siga siendo ortonormal.

Los `Node3D` forman una jerarquía invisible de articulaciones. Los cuerpos y cajas de colisión siguen esa jerarquía sin deformar una piel. La perspectiva de la cámara determina posición, oclusión y tamaño aparente. La selección de vistas usa dirección local y pesos continuos. La salida visible de Lie proviene de muestras de los sprites capturados y de receptores planos reconstruidos; no se dibujan las mallas del maestro.

Controles: arrastrar sobre el escenario o flechas para orbitar; rueda o deslizador para acercar; controles de altura, distancia y articulación; espacio o **Animar** para movimiento; **Luz**, **Pose** y **Rebote** para comparar estados. El interruptor de inspección crea una referencia nativa 3D separada, con la misma cámara y pose. Al salir de ella sus mallas se retiran de la escena Lie.

## Luz y metal

La iluminación directa se consulta desde cada muestra hacia la fuente y emplea su normal capturada. Conserva radios finitos, absorción y dos generaciones de emisores secundarios difusos con radios decrecientes. La irradiancia indirecta del suelo y la pared se interpola entre los centros de sus nodos para evitar escalones visibles. Las consultas de sombra reducen la caja 10 micrómetros por eje local para estabilizar contactos tangenciales entre float32 y float64; las capturas y sus cajas de percepción no se reducen. Los colores están en RGB lineal y son parámetros relativos, no potencia espectral calibrada.

El brillo visible añade Trowbridge–Reitz/GGX isotrópico, enmascaramiento Smith y Fresnel Schlick RGB. Cambia con la dirección de cámara sin capturas extra. Solo la fracción difusa participa en los nodos de rebote; los metales no se convierten en emisores difusos ficticios de toda su reflexión. Los ojos tienen una pequeña emisión decorativa local que no se inyecta al grafo como luz.

Referencias físicas: [Microfacet theory, PBRT 4e](https://www.pbr-book.org/4ed/Reflection_Models/Roughness_Using_Microfacet_Theory) y [Conductor BRDF](https://www.pbr-book.org/4ed/Reflection_Models/Conductor_BRDF). La implementación de Lie es una aproximación RGB con controles artísticos y no reproduce íntegramente el conductor espectral de PBRT.

## Trabajo que se evita

La versión anterior asignaba 16 384 posiciones por tarea aunque una vista tuviera menos píxeles útiles. LIE-15 forma rangos consecutivos de muestras reales; una búsqueda de prefijos en GPU localiza su tarea sin construir una lista CPU por píxel. La reserva compacta usa el número real de muestras del maestro × máximo de piezas. El despacho usa solamente la suma de las vistas activas.

Después de resolver la profundidad, una muestra comprueba si alguno de sus cuatro píxeles sobrevive. Solo entonces evalúa luces y material. Las pruebas comparan contra un consumidor con posiciones reservadas y sombreado incondicional, usando la **misma escena, cámara, luz y material**. Exigen igualdad de color, profundidad y propietario, y registran invocaciones, reservas y evaluaciones realmente evitadas. Los contadores describen trabajo; no equivalen a una medición de FPS de un dispositivo.

La referencia geométrica independiente intersecta rayos de cámara con los **70 triángulos originales**, transformados con la pose del robot. No usa los puntos capturados ni sustituye el maestro por cubos perfectos. La referencia radiométrica usa float64 e incluye normales escaladas, visibilidad, GGX y luz indirecta. La inspección visual nativa utiliza iluminación PBR de Godot y permite inspeccionar geometría, pero su iluminación no es idéntica al transporte de Lie.

## Reproducir

Requiere Blender, Python con NumPy para los oráculos y Godot 4.7.2 con Vulkan:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
blender --background --python-exit-code 1 --python tools/lie15_prepare_blender.py
blender --background --python-exit-code 1 --python tools/lie_capture_surface_blender.py -- --input gpu_compute/assets/lie15/master-neutral.glb --out gpu_compute/captures/robot_master --azimuth-steps 12 --elevations=-75,-35,0,35,75 --resolution 128
blender --background --python-exit-code 1 --python tools/lie15_pack_blender.py -- gpu_compute/captures/robot_master
python3 tools/lie15_reference.py gpu_compute/captures/robot_master
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie15_lab.tscn
# Prueba de render real:
godot --path gpu_compute --script res://test_lie15_robot.gd
```

CI usa Xvfb y Vulkan por software. El artefacto `lie-15-arcont-robot-evidence` incluye capturas, muestras, fuentes, PNG reales de cámara, 24 fotogramas de órbita/movimiento y diagnóstico numérico.

## Límites actuales

- Las sombras usan cajas orientadas aproximadas y omiten autosombra interna de una pieza. La geometría de profundidad visible sí proviene de capturas reales.
- La fusión de vistas y el splat 2 × 2 pueden dejar error de silueta y profundidad, especialmente de cerca. Los oráculos lo miden.
- La luz indirecta es difusa y gruesa; no incluye reflejos de entorno, rebote especular, cáusticas ni metal espectral.
- La animación reconstruye el grafo de transporte cuando cambia la pose. Los pares que no se enfrentan se descartan antes de consultar oclusión; todavía falta un cache incremental para escenas grandes.
- El compositor transparente de LIE-13 sigue en su laboratorio separado; este robot no pretende probar vidrio o líquidos integrados.
- No hay medición en GPU física ni Android. Esta entrega prueba funcionamiento, calidad geométrica y reducción de trabajo bajo Vulkan por software.
