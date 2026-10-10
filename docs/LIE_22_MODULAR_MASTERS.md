# LIE-22 · Ojo parametrizable y destrucción modular

Este paso añade dos pruebas al taller: un ojo con iris recoloreable, diámetro
pupilar y articulación invisible, y una pared de 48 ladrillos con agrupación,
revestimiento, daño local y fragmentos que usan la física nativa de Godot.
Las superficies originales de Blender nunca se rasterizan en Lie.

## Preparación y uso

```sh
blender --background --python-exit-code 1 --python tools/lie22_prepare_blender.py
python3 tools/lie22_verify_captures.py gpu_compute
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie22_modular_lab.tscn
```

También se abre mediante «Ojo y pared modular» en el taller de piezas.
El archivo editable `assets/lie22/modular-masters.blend` contiene originales
procedurales distribuidos bajo la licencia del proyecto. Diez maestros se
capturan con 36 direcciones a 96². El paquete compartido contiene posiciones,
radios, normales, gris, región de material y celda local, con 48 bytes por
muestra; dos niveles conservan distintos presupuestos de muestras. Las PNG
neutrales documentan tres vistas por maestro y no se cargan para renderizar.

## Representación y GPU

La biblioteca es inmutable y se sube una sola vez. Las instancias conservan
transformación, identidad de ladrillo y parámetros propios. Proyección,
profundidad, mezcla de material, luz, composición HDR y resolución lineal
ocurren en seis fases compute. La imagen interna de 768² se resuelve a 384².
El material se combina mediante huellas elípticas ponderadas y prueba de
profundidad; no se mezcla arbitrariamente el frente con el fondo.

La firma incluye cámara, luz, material, instancias y selección de capturas.
Una firma sin cambios reutiliza la imagen GPU completa; variar cámara o luz
requiere reconstrucción. No hay lectura de píxeles CPU por cuadro de usuario.
El diagnóstico sí lee GPU. El buffer de proyecciones crece por bloques y se
reutiliza; se informa su máximo residente, incluso después de restaurar la pared.

Presupuestos: 128 instancias y 750000 invocaciones de muestra. Con contribución
máxima de 256, la suma de pesos está acotada a 192 millones en uint32.
El constructor de trabajos verifica rangos, prefijos y coherencia con la
cantidad de muestras antes de publicar un paquete. Una escena grande cambia
al nivel conservador antes de exceder el contrato.

## Ojo

Esclerótica, iris y pupila tienen regiones independientes. Las fibras del iris
se capturan en gris; el color sRGB elegido por usuario/agente se convierte a
RGB lineal antes de aplicar material y luz. La pupila permanece oscura y su
radio cambia entre 0.8 y 3.2 mm mediante deformación radial de las muestras,
conservando el borde exterior del iris. La mirada rota todo el maestro.

El brillo húmedo usa un normal de recubrimiento esférico y GGX simplificado.
No hay una capa refractiva de córnea, reflexión completa del entorno, película
lagrimal ni párpados. El ojo aún no se inserta en el maestro humano de ojos
cerrados. No se afirma equivalencia anatómica o visual a Cycles.

## Pared, capas y daño

La rejilla tiene 6 columnas y 8 filas. Los ladrillos miden 0.24 × 0.065 × 0.11 m.
Doce módulos de 2 × 2 conservan muestras de sus superficies visibles; la pared
intacta utiliza 12 instancias de módulo y una del suelo. El modo expandido
utiliza 48 ladrillos compartidos y suelo. El revestimiento es un maestro de
superficie capturada con profundidad propia.

Cada celda acumula daño hasta 100. Al destruir una, solo su módulo se expande;
las demás celdas del módulo revelan ladrillo sin revestimiento. Las partes
expuestas, caras laterales y caras internas de cuatro fragmentos Voronoi ya
están capturadas. Los otros módulos permanecen agrupados. La variación de
color/rugosidad usa una semilla y la identidad persistente de cada ladrillo.

Un grafo de vecinos horizontales/verticales comprueba conexión con la primera
fila, tratada como apoyo. Las celdas sin conexión se convierten en cuerpos
rígidos independientes. Esto modela pérdida de conexión; no calcula esfuerzos,
flexión de vigas o ingeniería estructural. Tampoco produce cortes arbitrarios.

Godot simula gravedad, colisiones convexas y reposo con colliders invisibles.
Una nueva rotura conserva los cuerpos que ya existían. Hasta ocho ladrillos
destruidos, seleccionados por identidad, conservan cuatro fragmentos cada uno;
los demás agujeros siguen siendo válidos sin añadir más detalle pequeño.
Los ladrillos desconectados conservan sus cuerpos, dentro del límite de
instancias. Este presupuesto no representa una medición de capacidad Android.
Desactivar simulación congela cuerpos. Deshacer conserva los cuerpos que siguen
siendo válidos; rehacer o recargar regenera los cuerpos ausentes, sin recuperar
una trayectoria física exacta. El documento guarda apariencia y daño, no estados
completos de dinámica. Los cuerpos dormidos reutilizan sus transformaciones;
no se vuelven a dibujar si la firma visible tampoco cambia.

## API compartida

Los controles visuales ejecutan el mismo documento validado que los agentes.
Operaciones: `snapshot`, `set_values`, `strike`, `reset_wall`, `batch`,
`save_document`, `load_document`, `undo`, `redo`. Historial limitado a 64 estados;
`expected_revision` evita sobrescribir cambios concurrentes. Lotes inválidos
se rechazan completos. No se evalúa código arbitrario.

```json
{"op":"set_values","values":{"iris_color":[0.22,0.57,0.76],"pupil_radius":0.0024}}
{"op":"strike","cell":27,"energy":100}
```

El snapshot del taller devuelve inbox/outbox de `user://modular22`. Un agente
puede usar `tools/lie_workshop_client.py --directory <ruta retornada> ...` con
el mismo protocolo correlacionado. Guardar y abrir usan una ruta fija dentro
del directorio de usuario. El golpe también se puede seleccionar tocando la
imagen; el rayo se convierte a la celda visible en coordenadas de la pared.

## Verificación

El workflow prepara realmente Blender y ejecuta Vulkan sobre llvmpipe.
La prueba independiente comprueba 800 muestras contra las superficies fuente,
normalización, finitud, caras interiores y partición de volumen de ladrillo.
El documento prueba límites, transacciones, historial, persistencia, daño
acumulado y soporte. La prueba GPU usa botones reales y el agente sobre el
taller abierto; verifica cambio de color, geometría pupilar, cámara/luz,
agrupación, abertura por profundidad, física, preservación de cuerpos y
reutilización de biblioteca e imagen. Los PNG y JSON son capturas reales.
Tiempos de pases GPU no son tiempos de cuadro completos ni FPS móviles.

Materiales de madera, cables, fuego, deformación corporal y expresiones
faciales completas quedan fuera de estas dos pruebas. El catálogo y el
vínculo de apariencia hacen posible investigarlos después.
