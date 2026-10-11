# LIE-24 · Construcción facial con capturas intercambiables

Una cabeza conserva su volumen capturado y sustituye una región facial por
un asset compatible. La primera región es la nariz: base sin nariz, clásica,
corta y ancha. Los labios, cejas y mejillas siguen siendo los del escaneo;
todavía no existe una biblioteca completa de rasgos ni expresiones de boca.

## Construcción y unión

El maestro atribuido de LIE-23 aporta una superficie de captura, UV, rig y
párpados. La región nasal se retira por completo de las muestras base. Las
cuatro alternativas comparten el contorno externo del escaneo. Las tres
narices conservan además un collar de dos pasos de adyacencia. El interior
de las fosas nasales introduce un segundo contorno de montaje para esas
variantes. La base usa una triangulación restringida sin pliegues ni
solapamientos y suaviza profundidad y color desde su contorno externo; la
geometría interior de las fosas queda detrás de esa piel. Las variantes
modifican el relieve interior sin mover su collar.

Cada alternativa se captura desde 36 direcciones, normalmente a 160² sobre
una ventana de 10 cm. Guarda gris, filtro de color, normales, profundidad,
huella y asociación a su soporte. El color usa las UV del mismo maestro. Las
normales suaves de montaje se calculan sobre la superficie ensamblada completa.
No hay una prioridad de dibujo fija entre ojos, nariz y piel: la profundidad
común resuelve su visibilidad desde la cámara actual.

El cuarto entero de cada triángulo identifica su región: cero es la base
compartida, uno el relleno sin nariz y dos a cuatro las tres narices. Solo el
grupo correspondiente a `nose_index + 1` se proyecta. Las alternativas
inactivas tampoco escriben sombra ni material. Todos los datos se suben una
vez; cambiar de variante no vuelve a capturar ni subir el maestro.

## Soporte invisible adaptativo

Las regiones rígidas de la cabeza guardan directamente XYZ y normales de las
capturas, con `binding.w = -2`. Una transformación rígida las mueve con el
cráneo. Su volumen fino permanece en las muestras; no necesitan una malla
densa para deformarse. El cuello y los párpados conservan su asociación
baricéntrica y el parpadeo curvo de LIE-23. Las narices conservan un soporte
local de montaje. Ninguna de estas mallas se rasteriza en el laboratorio Lie.

El paquete sigue usando vértices de 96 bytes, triángulos de 16 y muestras de
80. `rigid_sample_encoding = local-xyz-head-v1` habilita la nueva asociación;
el cargador anterior sigue rechazando índices negativos si no se declara ese
contrato. En las muestras rígidas, `geometry_front.xyz` guarda la normal
geométrica; en las deformables sigue guardando la covarianza tangente.

Reducir el soporte no implica reducir toda la memoria. La biblioteca residente
incluye cuatro alternativas nasales y buffers de proyección para todas ellas.
La verificación informa por separado vértices, muestras, bytes fuente y reservas
del compositor. No se afirma una mejora de FPS ni un ahorro total sin medirlos.

## Taller y protocolo

El taller incluye «Construcción facial modular». Comparte controles de cámara,
luz, piel, mirada y parpadeo, y añade selección de nariz y variación con semilla.
Guardar, abrir, deshacer y rehacer conservan el módulo seleccionado.
El documento `lie-modular-face24` y su inbox/outbox en `user://face24` tienen
identidad separada de LIE-23. Una selección fraccionaria o inexistente se rechaza
antes de cambiar otros campos. La semilla se valida y se usa en un generador
local; no modifica el generador aleatorio global.

```json
{"op":"set_values","values":{"nose_index":2,"camera_yaw":90}}
{"op":"randomize","seed":17,"expected_revision":0}
```

`nose_index = 0` muestra la base. Los valores 1, 2 y 3 seleccionan las narices
clásica, corta y ancha. La variación aleatoria solo elige entre esos tres assets
de la familia `lee-face-v1`; no garantiza compatibilidad con otras familias.

## Reproducción y comprobación

```sh
blender --background --python-exit-code 1 --python tools/lie23_prepare_blender.py
blender --background --python-exit-code 1 --python tools/lie24_prepare_blender.py
python3 tools/lie24_verify_captures.py gpu_compute
godot --headless --path gpu_compute --script res://workshop/test_lie_modular_face_document.gd
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute --script res://test_lie24_modular_face.gd
python3 tools/lie24_compare_native.py gpu_compute
godot --path gpu_compute res://lie24_modular_face_lab.tscn
```

La verificación comprueba cada ensamblaje por separado: unión exacta, collar
intacto, integridad de buffers, una sola biblioteca ocular y presupuesto de
muestras. Blender produce referencias nativas de frente, a 45° y de perfil
para las cuatro alternativas, más un perfil opuesto. Una pose independiente
combina giro de cabeza y parpadeo cerrado. Vulkan compara las posiciones de
las muestras con esas poses, comprueba que las alternativas inactivas no tengan
propietarios y verifica que volver a una nariz restaure la misma imagen sin
nuevas subidas. La comparación de silueta exige IoU ≥ 0.985 y la de albedo de
piel MAE ≤ 0.03 en RGB normalizado. Las imágenes de belleza de Cycles tienen
iluminación y materiales aproximados; se usan para inspección visual.

El laboratorio dibuja un solo busto. Compartir la biblioteca entre múltiples
personajes simultáneos, variar proporciones de cabeza, añadir otros slots,
expresiones coordinadas y medir una GPU física/Android son trabajos posteriores.
