# LIE-16 — Calidad estable y coste medido de la cámara Lie

El mismo robot de Arcont de LIE-15 tiene una cámara nueva. Conserva un maestro
compartido y las quince articulaciones invisibles. La escena Lie no dibuja
mallas del maestro. Se compara con LIE-15 y con rayos contra los 70 triángulos
originales; no se sustituye la geometría original por cajas para la validación.

## Mezcla y cobertura

Las capturas conservan la mezcla angular continua de LIE-15. Cada muestra tiene
una huella correspondiente a su celda de captura, proyectada mediante la escala
y la orientación de su pieza. Una cobertura triangular acotada sustituye al
bloque fijo de 2 × 2. La profundidad en cada píxel se calcula sobre el plano
local de la muestra, en lugar de asignar la profundidad del centro a todo el
bloque. Esta es una aproximación de superficie capturada, no una malla visible.

Un paso adicional resuelve la muestra ganadora. La mezcla de color exige
profundidad cercana, la misma pieza y normales compatibles. Así se evita que
el color de una articulación vecina contamine la superficie más cercana. Los
límites actuales de profundidad y normal están explícitos en el shader.

La composición final interpola cuatro píxeles de la imagen Lie. Cada uno se
comprueba contra la profundidad nativa de Godot. Esta reconstrucción suaviza
bordes a costa de cierta suavidad; no recupera detalle que falta en la captura.

## Detalle según tamaño percibido

`tools/lie16_quality.py` genera niveles de celdas de 1, 2 y 4 píxeles a partir
del maestro capturado. Solo reduce celdas completas, coplanares, con normales,
nodos de material y gris compatibles. Bordes, huecos, cambios de material y
detalles finos conservan sus muestras originales. Una celda grande que falla
usa sus celdas menores, no un promedio que invente superficie.

La cámara estima el espaciado proyectado de la captura mediante distancia,
escala de la pieza y campo de visión. Las piezas pequeñas en pantalla pueden
usar menos muestras. Cerca de los umbrales hay una transición suave entre dos
niveles. Durante esa transición se despachan ambos niveles y el coste puede
subir temporalmente. Se mantiene la selección angular original; no se fuerza
un número pequeño de vistas que deje huecos.

El maestro incluye los tres niveles y sus huellas en un buffer compartido e
inmutable. Cambiar pose/cámara no vuelve a subirlo. La reserva de proyecciones
crece por potencias de dos según el trabajo requerido, permanece en su tamaño
máximo alcanzado y evita reservar todos los pares pieza/vista por adelantado.
Los niveles adicionales y el historial también consumen memoria: no se debe
confundir una reserva menor de proyección con una reducción de toda la RAM.

## Historial propio, ligado al esqueleto invisible

El efecto temporal se ejecuta dentro de la salida de Lie. Reconstruye el punto
actual con profundidad y cámara, lo transforma al espacio local de la pieza y
lo coloca en su pose anterior. Así encuentra su píxel anterior incluso si la
articulación se mueve. Suelo y pared usan coordenadas de mundo.

Se rechaza historia de otra pieza, otra profundidad, fuera de la cámara o sin
superficie actual. El color anterior se limita al rango del vecindario actual
de la misma pieza. Movimiento rápido y cambios de brillo reducen su peso. Una
secuencia de ocho desplazamientos de cámara menores de 0.3 píxeles por eje
aporta muestras subpíxel. La mezcla máxima del historial es 0.7.

Los cortes grandes de cámara, cambios de calidad, entrada/salida de la
inspección 3D y cambios de códigos de luz/material invalidan el historial. El
laboratorio transmite estos últimos con `set_lighting_signature()`. Otro
consumidor que cambie sus luces/materiales debe actualizar esa firma o llamar
`reset_history()`. Esto reduce estelas; no garantiza su ausencia para todos los
assets, deformaciones o animaciones futuros.

Se usan dos imágenes y dos buffers de metadatos alternados, para que ningún
píxel sobrescriba datos que otro hilo todavía necesita. La interacción normal
no descarga imágenes a CPU ni interpola fotogramas artificiales.

## Uso y reproducción

Abrir `gpu_compute/lie16_lab.tscn` tras preparar el mismo maestro de LIE-15:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
blender --background --python-exit-code 1 --python tools/lie15_prepare_blender.py
blender --background --python-exit-code 1 --python tools/lie_capture_surface_blender.py -- --input gpu_compute/assets/lie15/master-neutral.glb --out gpu_compute/captures/robot_master --azimuth-steps 12 --elevations=-75,-35,0,35,75 --resolution 128
blender --background --python-exit-code 1 --python tools/lie15_pack_blender.py -- gpu_compute/captures/robot_master
python3 tools/lie15_reference.py gpu_compute/captures/robot_master
python3 tools/lie16_quality.py gpu_compute/captures/robot_master
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie16_lab.tscn
godot --path gpu_compute --script res://test_lie16_quality.gd
```

Los controles de órbita, distancia, altura, articulación, luz e inspección 3D
se conservan. El selector añade **Equilibrado**, **Detalle completo** y **Sin
historial**. Los tres usan reconstrucción espacial; el segundo mantiene todas
las muestras y el tercero permite inspeccionar la salida sin reutilización
temporal. La resolución por defecto permanece en 384 × 384 para permitir
comparaciones honestas. Una instancia separada puede configurarse en 576 × 576
con las mismas capturas de 128 × 128.

## Evidencia y medición

El workflow `.github/workflows/lie-16.yml` ejecuta Vulkan real mediante
llvmpipe/Xvfb. El artefacto incluye las capturas, niveles, fuentes, imágenes
reales, pares de movimiento y `lie16-diagnostic.json`. Las pruebas cubren:

- Ocho casos numéricos independientes del shader temporal, incluyendo identidad,
  otra pieza, profundidad incompatible, fondo, corte, reinicio, cambio de luz y
  movimiento de una articulación que necesita su transformación anterior.
- Material directo/indirecto contra el oráculo float64 de LIE-15.
- Siete cámaras contra la malla original; comparación de detalle completo y
  adaptable, trabajo despachado y diferencias de imagen.
- Variación de color entre fotogramas en una escena quieta, comparando salida
  temporal y salida cruda de los mismos fotogramas con desplazamientos subpíxel.
- Reinicio al cambiar la luz, cero robot residual al apuntar fuera de escena,
  cero mallas visibles y una sola subida del maestro durante el movimiento.
- Timestamps del consumidor completo —reconstrucción, historial y composición—
  con la misma cámara lejana. Se excluyen transporte de luz y creación CPU del
  grafo de poses. Durante los intervalos medidos no se guardan PNG ni se hacen
  descargas de imágenes a CPU.

Los timestamps corresponden al driver de software de CI. No prueban FPS de una
GPU física, Android ni ventaja universal frente a rasterizar una malla sencilla.
La cadencia elegida al exportar el vídeo/GIF tampoco es una medición del motor.
Los efectos adicionales tienen coste y cada resultado debe leerse junto con su
error de imagen, cámara, modo y reserva de memoria.

Las sombras por cajas, iluminación indirecta difusa gruesa y limitaciones de
metal/reflejos de LIE-15 permanecen. Vidrio/líquidos de LIE-13 siguen separados.
No se promete fotorealismo universal ni un motor completo de producción.

Referencias primarias: [Godot RenderingDevice timestamps](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html#class-renderingdevice-method-capture-timestamp),
[Godot antialiasing y efectos temporales](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html),
[AMD temporal upscaling concepts](https://gpuopen.com/manuals/fidelityfx_sdk/fidelityfx_sdk-page_techniques_super-resolution-temporal/).
Lie usa su propia implementación acotada; no incluye FSR ni activa TAA nativo
de Godot para reconstruir automáticamente sus capturas.
