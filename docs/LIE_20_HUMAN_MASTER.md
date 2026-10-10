# LIE-20 · Maestro humano capturado y deformación invisible

El objetivo de este laboratorio es convertir un escaneo humano real en un
maestro que Lie pueda mover e iluminar sin dibujar la malla original. Es un
primer experimento de piel y deformación; no demuestra hiperrealismo humano
completo, independencia de Godot ni rendimiento móvil.

## Fuente y reproducción

Lee Perry-Smith / Infinite-Realities creó el escaneo. Los archivos distribuídos
en los ejemplos de three.js conservan licencia CC BY 3.0. Se mantienen la
atribución y el aviso original. `gpu_compute/assets/lie20/source-lock.json`
fija el commit, tamaños y SHA-256. El código de three.js no se integra.

Con Blender 4.x y Godot 4.7.2:

```sh
blender --background --python-exit-code 1 --python tools/lie20_prepare_blender.py
godot --headless --path gpu_compute --script res://workshop/test_lie_human_document.gd
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie20_human_lab.tscn
```

El exportador adquiere únicamente los cinco archivos fijados, comprueba sus
bytes y crea `human-master.blend`, con texturas empaquetadas, un armature nativo
Neck/Head, pesos y dos shape keys editables. La escala final mide 0.42 m en Y.
La versión cerrada del importador GLB solo admite este asset verificado.

## Apariencia y datos invisibles

Se capturan 36 cámaras ortográficas: 12 azimuts y tres elevaciones. Para cada
píxel, Blender/BVH calcula la primera superficie y guarda imagen gris, filtro
RGB lineal, normal detallada y profundidad. El color se conserva como
`gray * filter_rgb`; una pieza humana no tiene un único tinte uniforme.

Cada muestra mantiene triángulo de referencia y coordenadas baricéntricas.
El empaquetado elige muestras de capturas bien orientadas y deduplica celdas
espaciales conservando el frente más favorable. No se capturan luces distintas
ni cada fotograma de animación. Posiciones, triángulos y pesos son información
invisible que vincula y deforma las muestras; nunca se envían a una llamada de
rasterización de la malla original.

| Buffer | Bytes por registro | Función |
| --- | ---: | --- |
| Vértice invisible | 48 | Posición base, peso de cabeza, dos correctivos |
| Triángulo invisible | 16 | Tres índices para el vínculo de superficie |
| Muestra capturada | 80 | Vínculo, normal detallada, gris/filtro, material y normal geométrica |
| Muestra proyectada | 64 | Posición deformada, normal, pantalla y gradiente de profundidad |

La normal geométrica decide cobertura y profundidad; el detalle del normal
map afecta iluminación. Esto evita convertir los poros en falsos desplazamientos
de profundidad. La transformación del normal usa el inverso transpuesto del
mapa local entre el triángulo base y el deformado.

## Render y piel

Siete fases compute: deformación de vértices invisibles, limpieza, proyección
de muestras/depth de sombras, selección de ganadores, iluminación, difusión
horizontal y difusión vertical/composición. Las capturas se suben una vez.
Solo cambia un paquete de 240 bytes cuando se modifica cámara, pose o luz.
Un retrato quieto conserva su imagen GPU sin repetir las siete fases.

La luz directa usa GGX/Smith/Schlick con filtro de material. La rugosidad se
deriva artísticamente del antiguo mapa especular del escaneo; no es una medición
física de la piel. Un depth de 256² construido desde las muestras produce una
primera sombra propia.
La profundidad de cada huella de sombra se evalúa sobre su plano tangente
geométrico; extender la profundidad central como constante produce bandas
de sombra propia sobre superficies inclinadas.
La difusión RGB separable filtra luz difusa, preserva
el brillo especular y rechaza muestras de profundidad o normal incompatibles.
Es una aproximación en pantalla, no transporte volumétrico. El ambiente es
un término aproximado; aún no está conectado al grafo de rebotes humano.

La imagen 512² se muestra mediante Texture2DRD sin lectura CPU por fotograma.
Godot sigue proporcionando interfaz, cámara, contexto de render y drivers.
El diagnóstico y los tests sí hacen lecturas GPU explícitas.

## Taller y agentes

El taller de piezas tiene un acceso al inspector humano. Los controles de
cabeza, correctivos, cámara y piel comparten `lie_human_document.gd` con los
comandos JSON. Los valores se validan atómicamente, con revisión, historial
limitado, guardado y recarga. La animación evalúa controles sobre el maestro.
Este inspector todavía no añade humanos a las escenas de ensamblaje rígido.

Operaciones: `snapshot`, `set_values`, `set_playing`, `set_time`,
`save_document`, `load_document`, `undo`, `redo`. El inbox/outbox correlacionado
de `user://human` es compatible con el cliente Python existente:

```json
{"op":"set_values","expected_revision":0,"values":{"head_yaw":15,"sss":0.8}}
```

El snapshot devuelve las rutas concretas para usar
`tools/lie_workshop_client.py --directory ...`. No se permiten rutas de carga
arbitrarias ni operaciones fuera de este documento.

## Evidencia y criterios

El workflow LIE-20 ejecuta el pipeline real en Vulkan por software. Compara
128 posiciones vinculadas por pose con la evaluación nativa del armature y
shape keys de Blender, con error máximo permitido de 0.00002 m. También
comprueba reutilización de capturas, retrato estático sin trabajo repetido,
controles visuales, revisión de agentes y respuesta correlacionada.

Cinco vistas/poses fijas se comparan con renders originales independientes de
Blender/Cycles: neutro, giro, correctivos, perfil y acercamiento. El criterio
de silueta es IoU >= 0.96 para cada caso. Se informa el error RGB, pero no se
presenta como equivalencia física: Cycles usa otra dispersión, ambiente y sombra.
Los tiempos GPU delimitan las fases Lie; no representan un cuadro completo,
un teléfono o una GPU física. La cadencia de un video exportado no es FPS del
motor.

## Límites y camino al rostro completo

El escaneo tiene ojos cerrados, sin córneas, globos oculares, cabello ni interior
de boca. `lid_squeeze` y `jaw_drop` son offsets experimentales para comprobar
el vínculo de deformación, no parpadeo ni articulación oral anatómica.

Los siguientes maestros deben añadir ojos por capas, boca/dientes, expresiones
esculpidas con correctivos y cabello con dirección de fibras. También faltan
translucencia por espesor, rebotes humanos, tratamiento temporal deformable,
streaming/LOD de estos maestros y medición física en Android. El contrato de
superficie permite investigar esos pasos manteniendo Blender como autor.

Referencias técnicas estudiadas:

- Godot, Internal rendering architecture: https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html
- Jimenez et al., Separable Subsurface Scattering: https://www.iryoku.com/separable-sss/
- Qian et al., GaussianAvatars (precedente de apariencia vinculada a un modelo facial; no implementación utilizada): https://shenhanqian.github.io/gaussian-avatars
