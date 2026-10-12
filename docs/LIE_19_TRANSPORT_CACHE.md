# LIE-19: transporte reutilizado y cliente del taller abierto

Cambiar una lámpara en LIE-18 reconstruía también el grafo de visibilidad,
aunque las piezas permanecieran inmóviles. Ahora el grafo depende únicamente
de posiciones, normales, áreas y bloqueadores. Se conserva al cambiar luz,
color, absorción, rugosidad, metal, generaciones de rebote o transmisión del
agua. Esos cambios siguen resolviendo la iluminación y actualizando la imagen.
Mover, rotar, escalar o añadir piezas reconstruye el grafo. La animación rígida
también lo reconstruye cuando cambia su geometría evaluada.

La clave contiene los valores float32 exactos que utilizan los shaders, sin
un hash aproximado ni un umbral de movimiento. Se compara con el último
paquete consumido por el hilo de renderizado. Reemplazar un paquete pendiente
con otro cambio no permite reutilizar un grafo de una pose antigua. Los
parches, instancias y luces siguen publicándose juntos.

La matriz de factores se inicializa una vez en GPU; ya no se crea ni se
transfiere una matriz de ceros por edición. Cada buffer de entrada se compara
con su versión residente y sólo se transfiere cuando cambia. Las capturas
siguen compartidas: no se vuelven a tomar fotos por pose o animación.

## Medir desde los controles o desde un agente

Activa «Medir renderizado» en el taller. La interfaz muestra el número de
grafos construidos/reutilizados y la mediana de duración de las pasadas
visuales de Lie en el dispositivo actual. No es el tiempo total de un cuadro.
El inspector tiene desplazamiento vertical y los tres campos XYZ se ajustan
al ancho disponible.

La API de la escena añade dos comandos de ejecución, fuera del documento
guardado y del historial de deshacer:

```json
{"op":"runtime_profile","enabled":true}
```

```json
{"op":"runtime_metrics"}
```

Ambos admiten `expected_revision`. El primero sincroniza la casilla visible;
el segundo consulta las métricas disponibles sin leer imágenes completas de
GPU. `agent_snapshot()` incluye estas capacidades, métricas y rutas absolutas
de la bandeja. El perfil conserva hasta 180 muestras por pasada.

Las duraciones GPU se guardan también en nanosegundos Vulkan sin convertir,
con seriales de resolución. El perfil de transporte separa grafo e iluminación;
registra bytes transferidos, despachos y preparación CPU. Las muestras del
consumidor corresponden a sus propias pasadas, incluida su composición final.
La última preparación de estado CPU se mide por separado. Estas medidas no
incluyen la pasada óptica ni todo el trabajo de Godot.

## Cliente Python sobre la escena abierta

`tools/lie_workshop_client.py` usa sólo la biblioteca estándar de Python.
Utiliza la carpeta absoluta que aparece en `agent_snapshot()["inbox"]`,
quitando el nombre `inbox.json`. El taller debe estar abierto y preparado.

```bash
python3 tools/lie_workshop_client.py --directory /ruta/al/workshop
```

La respuesta contiene el snapshot y su revisión. Para editar esa revisión:

```bash
python3 tools/lie_workshop_client.py --directory /ruta/al/workshop \
  --expected-revision 7 \
  --command '{"op":"set_key","id":"head","time":1,"angle_deg":25}'
```

También acepta `--file comando.json`, `--timeout 30` y
`--output respuesta.json`. La salida de proceso es 0 si el taller acepta,
1 si rechaza el comando y 2 ante un problema local o timeout. No reintenta
automáticamente una edición que podría ejecutarse después del timeout.

El cliente publica un archivo completo mediante enlace atómico y nunca
sobrescribe una bandeja pendiente. Envuelve cada petición con un identificador
único, que el taller devuelve. Sólo acepta la respuesta correspondiente;
una respuesta antigua o incompleta se ignora. Un bloqueo local evita dos
clientes simultáneos. Un bloqueo abandonado tras cerrar abruptamente un
cliente se debe revisar antes de eliminar. El protocolo anterior, con un
comando JSON directo, continúa funcionando. Sigue siendo una bandeja local
de un único productor, no un servicio remoto ni una cola multiusuario.

## Verificación

El workflow del taller ejecuta las 44 comprobaciones de documento, las pruebas
Python y la aceptación Vulkan anterior. `test_lie19_cache.gd` añade cambios
de luces/materiales/agua y cambios geométricos; compara factores e irradiancia
con una reconstrucción completa deliberada. También verifica ediciones
pendientes, inactividad y un cliente Python real que modifica el taller y
recibe el rechazo de una revisión antigua.

La comparación temporal intercala pares con la misma edición de luz y el
mismo estado geométrico, con caché y con reconstrucción forzada. El artefacto
incluye `lie19-diagnostic.json`, nanosegundos sin convertir y una captura real
de la interfaz. El dispositivo CI es llvmpipe, Vulkan por software. El ahorro
de trabajo y las mediciones de estas pasadas no demuestran FPS en Android ni
en una GPU física, ni resuelven todavía la dinámica de colisiones o fluidos.
