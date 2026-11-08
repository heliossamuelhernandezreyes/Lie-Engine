# LIE 6.2: volúmenes invisibles agrupados por muro

La propuesta del usuario se prueba como una capa física independiente de la
apariencia capturada. Un muro rectangular cerrado puede usar una caja. La
esquina actual tiene una ventana y un muro de retorno: se representa mediante
cuatro cajas alrededor del hueco y una caja lateral. No se dibujan esas cajas.

## Alcance concreto

`lie_construction_proxy.gd` conserva la asociación de cada pieza con su ID,
propietario, banco, maestro, transformación y LOD. Construye `StaticBody3D`
con `BoxShape3D` en una capa física reservada. No crea `MeshInstance3D`, no
duplica los bancos de captura y no añade triángulos al compositor.

El modo por pieza genera una caja orientada por cada uno de los 781 elementos.
El modo agrupado de `corner` genera cinco cajas: izquierda, derecha, debajo y
encima de la ventana, más el muro lateral. Equivaldrían a 60 triángulos si se
convirtieran en mallas de cajas; los triángulos de proxy dibujados son cero.
Los dos modos conservan los 781 registros de apariencia.

La reducción de 781 a 5 es de cuerpos/formas de colisión en esta prueba, no de
las instancias visuales ni de los parches de luz. El campo sigue teniendo 4,742
parches y la apariencia conserva sus 1,165,568 muestras al usar el caso original.
No se modifica la reconstrucción, no se vuelve a capturar la pared y no se
convierte su relieve en una textura plana.

El agrupado es una **envolvente física de autoría**, no la unión exacta de
superficies del escaneo. Rellena pequeñas juntas y simplifica irregularidades.
Respeta la abertura libre declarada en la receta. No se usa esta envolvente como
oclusor visual ni como sustituto de la geometría del campo de iluminación.
Los demás conjuntos mantienen cajas por pieza; en particular, la hoja de puerta
permanece independiente y sus colisiones siguen su transformación de bisagra.

## Cámara

El control `Cámara con colisión` limita el recorrido desde la posición anterior
hasta la posición solicitada por el comando de cámara. Se consulta el mismo
conjunto de volúmenes antes de publicar la pose al consumidor LIE. La orientación
se vuelve a calcular hacia el objetivo después de frenar el movimiento.

La consulta inmediata usa una esfera de radio 0.025 m y cajas expandidas: es
conservadora, con 0.002 m de separación. Cerca de esquinas redondeadas puede
detenerse un poco antes que una esfera exacta. Los inicios ya solapados se
informan explícitamente; no se toma el resultado de `cast_motion` como prueba
de ausencia de colisión en ese caso. La prueba axial contrasta la fracción de
movimiento con una esfera real de `PhysicsDirectSpaceState3D.cast_motion`.

La cámara con colisión empieza desactivada para conservar las vistas anteriores
y permitir comparar las imágenes. Se activa en el control visible. Cambiar de
escena reinicia la trayectoria de cámara; no se interpreta un salto entre escenas
como un movimiento físico continuo.

## Prueba automática en el teléfono

La nueva escena de entrada ofrece `Probar muros y copiar`, sin desplazar el panel.
La prueba fija `corner`, semilla 2102 y desactiva temporalmente la limitación de
cámara. Conserva la resolución, la vista y las condiciones de luz elegidas.
Ejecuta modo por pieza y modo agrupado tras sincronizar cuatro frames de física.

Por cada modo registra:

- cuerpos y formas de colisión realmente creados;
- un rayo que debe chocar con la pared y otro que debe cruzar la ventana;
- una esfera del motor que se mueve contra ambas zonas;
- la consulta de cámara sobre las mismas trayectorias;
- 512 consultas de rayos alternadas, con tiempo CPU transcurrido y percentiles;
- recursos y contadores de reconstrucción y de campo.

Restaura los ajustes al finalizar y copia el informe si la prueba está completa.
El experimento no hace lecturas GPU de imágenes ni usa el menor número de cajas
para inferir una ganancia de FPS. El benchmark anterior de cámara/luz continúa
disponible con su botón original.

## Comprobaciones

`test_lie_proxy_physics.gd` ejecuta física real, también en headless: dos semillas,
781/5 cajas, asociación de todos los propietarios, liberación de cuerpos,
rayos, esferas, ventana, solapamiento inicial y puerta cerrada/abierta. Son 50
comprobaciones en Godot 4.7.2, con los catálogos originales.

`test_lie_proxy_gpu.gd` comprueba la entrada móvil, transacciones inválidas,
imagen/profundidad/sombra exactas entre modos, reutilización de campo y caché,
una reconstrucción independiente forzada por orden de bancos, informe copiado y
la publicación de una pose realmente limitada por colisión. Las regresiones
anteriores comparan diez estados de apariencia con el código fijado 6.1.

Vulkan de CI es software: valida los resultados y la integración, sin establecer
el rendimiento del Poco. La entrega conserva pruebas y checkpoint con el SHA de
APK, banco, código y resultados efectivos.

## Límites y trabajo posterior

Este experimento añade física y consultas de cámara. No añade todavía una
selección de muestras por muros ni oclusión jerárquica. Reducir cuerpos de física
no elimina automáticamente la reconstrucción de muestras. Para usar las paredes
como guía de visibilidad habrá que crear un contrato conservador independiente
que mantenga ventanas, relieve y sombras, y contrastarlo con las imágenes
actuales. La envolvente física que rellena juntas no es por sí sola una prueba
segura de oclusión visual.

Fuentes primarias:

- [Godot: collision shapes 3D](https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html)
- [Godot: PhysicsDirectSpaceState3D y límites de cast_motion](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html)
- [Godot: PhysicsBody3D](https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html)
- [Godot: occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)
