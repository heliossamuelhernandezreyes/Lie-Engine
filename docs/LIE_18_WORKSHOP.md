# LIE-18: taller de piezas, articulaciones y API para agentes

El robot anterior se montaba mediante matrices y curvas escritas en código.
Este taller convierte el montaje en un documento editable. Sus controles y
los agentes ejecutan los mismos comandos validados. La salida visible se
reconstruye con capturas; los maestros originales no se dibujan.

## Primera versión funcional

- Biblioteca de bloque/chapa de Arcont y cilindro original. La chapa reutiliza
  el maestro de bloque con escala controlada; el cilindro tiene capturas propias.
- Hasta 30 piezas con identificadores y ranuras estables. Duplicar una pieza
  comparte sus capturas; cada instancia conserva posición, material y rig.
- Selección en lista o mediante cajas invisibles; arrastre en el plano de la
  cámara, órbita, escala, orientación y acoplamiento de caras.
- Jerarquía de articulaciones con pivote, eje y límites. La escala de una pieza
  no escala las articulaciones de sus hijas. El rig es cinemático.
- Claves de ángulo, interpolación suave, tiempo absoluto, reproducción,
  edición de pose y registro de claves. No se generan fotos por animación.
- Materiales en RGB lineal, color elegido en sRGB, rugosidad y metal. Los
  materiales son compartidos por nombre; cambiar uno afecta sus instancias.
- Guardar/abrir `.lie.json`, deshacer/rehacer y rechazo atómico de cambios
  inválidos. Los guardados conservan precisión de transformaciones.
- Controles de luz, rebotes, historia temporal, contornos, agua y lluvia.
- Dock de Godot para abrir el taller. La primera interfaz se ejecuta como
  escena de autoría; no es un Blender incrustado ni un fork completo de Godot.

## Abrir

El proyecto `gpu_compute/project.godot` abre `lie18_workshop.tscn`.
Necesita los dos maestros preparados. El workflow LIE-18 prepara los assets,
captura cada maestro aislado, empaqueta sus datos y conserva las fuentes y
capturas en su artefacto. Las fuentes de cilindro incluyen `.blend` y `.glb`.
El bloque sigue siendo el asset real Kenney CC0 identificado en LIE-15.
Las fuentes editables están bajo `.gdignore`: Godot no intenta importarlas
con Blender al abrir el proyecto. Lie carga sus paquetes de capturas.

La preparación usa las herramientas existentes de Blender. Por maestro se
capturan 60 vistas neutrales, 128×128, con un mapa normal y profundidad por
vista. Las capturas se hacen al preparar el maestro, no al montar o animar.
Cambiar la geometría del maestro requiere regenerar su paquete. Esta primera
versión registra dos maestros; el importador de catálogos arbitrarios queda
como extensión posterior. Blender permanece externo.

## API común

`workshop/lie_document.gd` implementa el estado y sus validaciones. La escena
expone `command(request)` y `agent_snapshot()`. `command` actualiza tanto el
documento como los controles y el renderizador; no hay un camino paralelo que
omita validaciones. Se acepta JSON, sin evaluación de código arbitrario.

```json
{
  "op": "batch",
  "expected_revision": 0,
  "commands": [
    {"op": "duplicate_piece", "source": "head", "id": "helmet",
     "values": {"parent": "head", "position": [0, 0.27, 0],
                "scale": [0.65, 0.08, 0.52], "material": "paint"}},
    {"op": "set_track", "id": "head", "keys": [[0, 0], [1, 30], [2, 0]]},
    {"op": "set_settings", "values": {"fluid": "water"}}
  ]
}
```

`expected_revision` permite evitar cambios basados en una revisión antigua.
Los comandos de un `batch` se aplican juntos o se rechazan juntos. Un rechazo
conserva el documento y el historial. No se permiten ciclos, padres ausentes,
escalas singulares, números no finitos, claves fuera de orden/rango ni
presupuestos de piezas/óptica excesivos.

| Comando | Campos principales |
| --- | --- |
| `snapshot` | Devuelve documento, revisión y capacidades |
| `add_piece` | `id`, `values` |
| `duplicate_piece` | `id`, `source`, `values` |
| `update_piece` | `id`, `values` |
| `remove_piece` | `id`; incluye descendientes y sus pistas |
| `set_track` | `id`, `keys`: pares `[segundos, grados]` |
| `set_key` | `id`, `time`, `angle_deg`; añade o reemplaza una clave |
| `set_light` | `index`, `values`: posición, potencia RGB, radio |
| `set_material` | `name`, `values`: tinte lineal y parámetros |
| `set_camera` | `values`: `yaw_deg`, `elevation_deg`, `distance` |
| `set_settings` | `values`: rebotes, calidad y óptica |
| `set_time` | `value`; pausa y muestra esa pose |
| `set_playing` | `value`: booleano |
| `undo`, `redo` | Cambian una transacción completa |
| `batch` | `commands`, opcional `expected_revision` |

Cada pieza tiene `master`, `parent`, `position` del pivote respecto a su padre,
`rotation_deg` de reposo, `offset` del centro visible respecto a su pivote,
`scale` de su geometría, `axis`, `limits_deg`, `angle_deg` y `material`.
Las ranuras son asignadas por el documento y no son editables.
La pose manual actualiza la clave del tiempo actual cuando ya existe una
pista; conserva las otras claves. «Registrar clave» también conserva la pista.

### Agente sin interfaz

```bash
godot --headless --path gpu_compute \
  --script res://workshop/lie_agent_cli.gd -- \
  res://workshop/examples/agent-commands.json /absolute/path/response.json
```

El archivo de entrada contiene `commands` y opcionalmente `document`. La salida
contiene resultados, documento actualizado y avisos de colisión. Este modo
puede preparar documentos sin GPU; no sustituye la prueba del renderizador.

### Agente sobre el taller abierto

El taller observa `user://workshop/inbox.json` cada 0.2 s. Escribe un comando
JSON, preferiblemente con `expected_revision`, mediante archivo temporal y
renombrado atómico. La escena lo consume y publica
`user://workshop/outbox.json` con resultado y snapshot. `agent_snapshot()`
devuelve las rutas absolutas de esa instancia. Un único productor debe
escribir la bandeja; no es una cola concurrente ni un servicio remoto.
Para reintentar un cambio, consulta la revisión devuelta antes de enviar otro.

## Transporte y fluidez

Los buffers de instancia, parches, materiales y luces se publican juntos en
el hilo de renderizado. El consumidor usa las poses y tipos de maestro que
acaba de consumir el productor; no mezcla poses nuevas con luces antiguas.
Los dos maestros se empaquetan en un único buffer inmutable, compartido por
todas las instancias. Los niveles conservadores y la historia rígida de
LIE-16 y los contornos de LIE-17 se conservan.

El grafo de transferencia se construye en GPU: acoplamiento con visibilidad
de cajas orientadas, sumas por fila y normalización simétrica. Esta acota la
energía y conserva reciprocidad ponderada por área. Ya no se construye una
matriz de visibilidad O(N²) en GDScript cada vez que el robot se mueve. Una
escena inactiva conserva el transporte; no vuelve a resolverlo por cuadro.
Esto elimina trabajo CPU concreto, pero no establece por sí solo una mejora
de FPS: el coste total debe medirse en hardware objetivo.

Cambios de material, luz, maestro o topología invalidan historia; animación
rígida continua utiliza reproyección por pieza. No se reciclan IDs de historia
sin invalidarla. Los hooks nuevos conservan los defaults de LIE-16/17.

## Colisiones, agua y lluvia

Hay `AnimatableBody3D` y cajas orientadas invisibles por pieza. El análisis usa
15 ejes SAT, permite contacto y excluye vecinos conectados deliberadamente.
Se avisan penetraciones entre piezas no conectadas y con el piso. Los avisos
no son un solucionador de dinámica ni bloquean todas las poses posibles.
Los límites de articulación sí rechazan ediciones inválidas. Las cajas de
cilindros son conservadoras, así que algunos avisos pueden ser falsos positivos.
La animación de ejemplo se comprueba en 120 muestras de su ciclo completo:
los brazos se balancean hacia delante/atrás y no atraviesan el torso o la cadera.

Agua y gotas reutilizan los sprites neutrales de LIE-13. La composición lee la
salida actual de Lie, conserva profundidad opaca y usa imágenes separadas para
evitar realimentación refractiva. El agua emplea Fresnel, absorción por espesor
y ondas de normales cuyas derivadas se convierten a unidades del tamaño físico
de la superficie. La transmisión del medio se aplica también a la luz directa
del renderizador opaco, además del transporte de rebotes.

La lluvia utiliza caída balística con gravedad 9.81 m/s² y fase determinista.
El segmento de toda la caída se contrasta con los sólidos de la pose actual;
la gota se oculta después del impacto hasta su siguiente ciclo. Esto evita
túneles de muestreo de fotograma para sólidos estáticos, pero no resuelve
colisiones continuas de sólidos móviles ni produce salpicaduras. Las gotas
son sprites curvos; el agua no es una simulación volumétrica.

Sin fluido, la pasada óptica no se inicializa ni se despacha. Con fluido, hay
un presupuesto de cuatro capas y hasta 24 gotas en esta interfaz. No hay
refracción fuera de pantalla, cáusticas ni reflexión completa del entorno.

## Verificación

- `workshop/test_lie_document.gd`: transacciones, conflictos de revisión,
  ciclos, números no finitos, límites, escalas, pistas, deshacer/rehacer,
  persistencia, OBB, caída y API de cámara/material.
- `test_lie18_workshop.gd`: Vulkan real, botón visible de duplicación,
  comandos sobre la escena abierta, bandeja de agente, captura compartida,
  iluminación cambiante, óptica integrada y fotogramas de movimiento.
- El grafo GPU se compara con un oráculo CPU independiente de visibilidad y
  transferencia; además se verifican filas acotadas y reciprocidad por área.
- Las pruebas previas se conservan. El workflow produce diagnóstico y PNG
  reales; su dispositivo llvmpipe es un renderizador por software.

No se afirma rendimiento Android, integración de Blender dentro del taller,
animación de piel/ropa ni un motor de videojuegos completo con todos sus
editores. Es el primer taller funcional conectado al renderizador Lie.
