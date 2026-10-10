# LIE-23 · Rostro, mirada y parpadeo

El ojo de LIE-22 se integra en una versión modificada del maestro humano de
Lee Perry-Smith / Infinite-Realities, CC BY 3.0. La preparación abre las
órbitas del escaneo cerrado y añade dos anillos de párpado con un shape key
de cierre continuo. El escaneo original queda oculto dentro del .blend.
Esta reconstrucción de párpados es artística; no se presenta como anatomía
completa ni como equivalencia a Cycles.

## Preparación y taller

```sh
blender --background --python-exit-code 1 --python tools/lie23_prepare_blender.py
python3 tools/lie23_verify_captures.py gpu_compute
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie23_face_lab.tscn
```

El taller de ensamblaje también tiene «Rostro, mirada y parpadeo». Hay controles
para cabeza, cierre de párpados, mirada horizontal/vertical, radio pupilar,
iris, tono de piel, cámara y luz. Busto/Rostro/Ojos cambian el encuadre.
La animación de cuatro segundos combina mirada, giro y un pulso de parpadeo;
el slider de cierre conserva su valor de autoría. Guardar, abrir, deshacer y
rehacer usan el mismo documento que los agentes.

## Captura y datos compartidos

La piel y los párpados se capturan desde 36 direcciones a 384² con gris,
filtro regional, normales, profundidad y asociación baricéntrica a la superficie
invisible. El ojo neutral se captura con el procedimiento de LIE-22 a 96².
Se conserva una única copia de sus muestras en el buffer, invocada para dos
anclajes. Cambiar color, pupila, mirada, cabeza o parpadeo no necesita más fotos.
Cada humano puede reutilizar estos maestros y tener sus parámetros propios;
esta prueba todavía dibuja un solo busto.

Los buffers son `vertices.bin` (48 bytes/vértice), `triangles.bin`
(16 bytes/triángulo) y `samples.bin` (80 bytes/muestra). Las muestras de piel
conservan triángulo y coordenadas baricéntricas. Las del ojo conservan posición
local y región esclerótica/iris/pupila. El manifiesto distingue muestras
almacenadas de invocaciones; estas últimas cuentan dos veces el ojo. El límite
es un millón de invocaciones y un paquete de parámetros de 320 bytes.

El tono de piel multiplica el filtro regional capturado en espacio RGB lineal;
no simula melanina ni cambia automáticamente la difusión según pigmentación.
El iris usa fibras en gris y color configurable. El radio pupilar cambia entre
0.8 y 3.2 mm conservando el borde externo del iris. Los dos ojos siguen la
cabeza y usan una misma mirada en esta versión; no hay vergencia independiente.

## Profundidad, material e iluminación

Un compositor compute resuelve piel, párpados y ojos en los mismos buffers de
profundidad, propietarios y sombra. Las mallas fuente nunca se rasterizan.
Las muestras deformables siguen la superficie y el rig; las rígidas usan el
anclaje ocular, mirada y radio de pupila. La imagen interna de 1024² se resuelve
linealmente a 512² antes de exposición, compresión HDR y conversión sRGB.

Nueve fases: deformación, limpieza, profundidad/sombra, elección de propietario,
acumulación de material, iluminación, difusión horizontal, difusión/composición
vertical y resolución. El propietario queda resuelto antes de acumular material,
evitando que un iris cercano se mezcle con el párpado que lo oculta. La difusión
también respeta las regiones. El parpadeo no apaga ni recorta analíticamente el
ojo: los párpados lo ocultan mediante profundidad real de sus capturas.

El brillo ocular usa un normal esférico con GGX como recubrimiento aproximado.
No hay transmisión/refracción de córnea, película lagrimal, reflejo completo
del entorno, pestañas o pelo. La piel mantiene la difusión aproximada de LIE-21.
No se añade un transporte indirecto completo ni un rostro emocional completo.

Los buffers fuente se suben una vez. Un estado evaluado sin cambios reutiliza
la imagen GPU. Se informa el espacio de buffers/texturas propios del compositor;
esa cifra excluye memoria CPU, motor, controlador y otros sistemas. La lectura
de píxeles solo se activa en diagnóstico. No hay mediciones de Android.

## API y evidencia

El documento validado admite `snapshot`, `set_values`, `set_playing`, `set_time`,
`undo`, `redo`, `save_document` y `load_document`; historial máximo 64.
`expected_revision` protege contra ediciones concurrentes. Colores y todos los
valores numéricos se validan antes de cambiar cualquier campo. Inbox/outbox en
`user://face23` reutilizan el cliente `tools/lie_workshop_client.py` con respuestas
correlacionadas. No se evalúa código arbitrario ni se importa una ruta enviada
por el agente.

```json
{"op":"set_values","values":{"blink":0.5,"gaze_yaw":20,"iris_color":[0.37,0.62,0.28]}}
{"op":"set_values","values":{"skin_tint":[0.55,0.42,0.32],"framing":"face"}}
```

El .blend conserva rig nativo, shape key de parpadeo y claves pupilares. Blender
evalúa cinco casos con distintas cabezas, párpados, miradas y pupilas, y exporta
160 puntos de piel/párpados y 32 por ojo en cada caso. La prueba Vulkan compara
sus posiciones con las calculadas por GPU; comprueba también que ambos ojos
sean visibles abiertos, el cierre reduzca su visibilidad y el iris no coloree
párpados cerrados. Prueba controles reales, material, pupila, cámara, transporte
de agentes, presupuesto y reutilización. PNG y video de evidencia proceden de
fotogramas reales; su reproducción no representa FPS móviles.

Articulaciones del cuerpo, interior de boca y expresiones emocionales completas
requieren otros maestros y validación; no se atribuyen a este hito.
