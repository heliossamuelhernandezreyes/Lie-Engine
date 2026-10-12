# LIE-28 — Maestros para construcción modular

LIE-28 prueba una casa ensamblada con una biblioteca compartida de capturas,
sin dibujar las mallas originales. Conserva LIE-27 como entrada predeterminada.
Se abre desde el dock Lie del editor o con `tools/lie_agent_launch.py --lab lie28`.
Las capturas PNG se publican mediante archivo temporal y renombrado atómico.
La UI y el agente usan el mismo `command()`; el protocolo existente permite
descubrir controles, guardar/abrir estados y capturar el compositor o la ventana.

## Materiales encontrados y adquiridos

Se consultó la API pública de Poly Haven. Los recursos utilizados son texturas,
no modelos 3D de ladrillos rotos descargados. La geometría de todos los maestros
se creó para este experimento en Blender; los fragmentos derivan del mismo padre.

| Material | Fuente y autor | Mapas utilizados | Licencia de los mapas |
| --- | --- | --- | --- |
| Ladrillo envejecido | [Factory Brick](https://polyhaven.com/a/factory_brick), Rob Tuytel | Diffuse y Rough, JPG 1K | CC0-1.0 |
| Hormigón de encofrado | [Concrete](https://polyhaven.com/a/concrete), Rob Tuytel | Diffuse y Rough, JPG 1K | CC0-1.0 |

[Licencia oficial](https://polyhaven.com/license). Se descargaron solamente los
mapas originales, no las imágenes de ejemplo de la web. Cada archivo conserva
URL, autor, tamaño, MD5 del proveedor y SHA-256 local en `provenance.json` y en
el catálogo. El generador comprueba esos SHA-256 antes de utilizarlos.

Para cada cara de ladrillo se asigna un recorte interior de la fotografía,
excluyendo las juntas del material de muro. La geometría produce las juntas
verdaderas. Los recortes están declarados en el generador, no se pretende que
sean cuatro fotografías independientes de ladrillos completos.

El color sRGB se convierte a albedo lineal; la rugosidad se trata como dato.
Los valores capturados no incluyen iluminación. Las normales son geométricas;
normal maps y displacement de los recursos todavía no se incorporan.
Las caras nuevas de fractura usan un material de arcilla procedural propio.

## Biblioteca de maestros

Unidades: metros. Ejes: Y arriba, Z positivo al frente. Pivote de los muros en
el centro; colocar a Y=0.4 para apoyar el primer módulo en el suelo. Los GLB
conservan estos ejes sin una segunda conversión de Blender.

| Maestro | Dimensiones / función |
| --- | --- |
| `brick` | 0.24 × 0.07 × 0.12 m, con bisel físico de 1.5 mm |
| `half_brick` | 0.115 × 0.07 × 0.12 m |
| `hollow_block` | 0.39 × 0.19 × 0.20 m, dos huecos verticales reales |
| `concrete_panel` | 1 × 0.8 × 0.12 m |
| `slab` | 1 × 0.10 × 1 m, suelo y cubierta |
| `lintel` | 1 × 0.08 × 0.16 m |
| `corner` | Dos tramos en L de 0.25 m, altura 0.8 m y espesor 0.12 m |
| `wall` | 1 × 0.8 × 0.12 m; 10 hiladas, paso 0.25 × 0.08 m, aparejo alternado |
| `window_wall` | Módulo de muro con abertura de 0.50 × 0.48 m |
| `door_base` | Dos jambas; abertura de 0.75 m en toda la altura del módulo |
| `door_head` | Abertura inferior de 0.75 × 0.32 m y muro encima |
| `fragment_0`…`fragment_3` | Cuatro celdas de Voronoi cerradas, complementarias del ladrillo biselado |

Son 15 maestros en total. Cada uno tiene GLB con materiales y UV, y un objeto
marcado como asset en `building-masters.blend`, con las imágenes empaquetadas.
En ese archivo solo el ladrillo está visible inicialmente para evitar que los
maestros superpuestos al origen dificulten su inspección. Los GLB de fragmentos
comparten el origen del padre: se reconstruyen con transformaciones identidad.
La biblioteca capturada centra cada fragmento y registra su `origin_offset`;
el runtime vuelve a aplicar ese desplazamiento al reunirlos. Todos comparten
la identidad de material para evitar diferencias de color entre piezas reunidas.

## Captura y reconstrucción

36 direcciones por maestro, resolución 128², dos niveles de detalle.
659,432 muestras; banco de 52,754,560 bytes, una sola carga GPU.
Cada muestra usa 80 bytes: posición/radio, normal geométrica, zona/celda/
rugosidad, albedo RGB lineal y límites de apoyo de la cara en sus dos ejes
dominantes. Los fragmentos y medios ladrillos mantienen la densidad del padre.

Se reutiliza el compositor LIE-22 con tres métodos de configuración: raíz,
stride y recurso de shader. Sus valores predeterminados siguen siendo los de
LIE-22 (48 bytes). LIE-28 agrega albedo RGB y apoyo de cara a su shader propio.
Al proyectar una muestra, el punto de la cámara se convierte a coordenadas
locales y se limita a la cara fuente. Así el LOD grueso no tapa juntas o huecos
con discos de muestras vecinas. Los límites son rectangulares en los ejes
dominantes: no constituyen todavía un recorte de polígono arbitrario exacto
para las caras oblicuas de fractura. La fuente de fractura sí es cerrada y exacta.

La casa usa 79 instancias y 545,732 invocaciones en LOD grueso. Tiene interior
de 4 × 3 m, altura de 2.4 m, puerta de 0.75 × 1.92 m,
ventanas, esquineros de hormigón, losas de suelo y cubierta desmontable.
La cubierta reutiliza las losas con una escala horizontal pequeña para tapar
el espesor exterior de los muros. Los esquineros y el dintel son inserciones
visuales; no se modelan uniones constructivas ni el cálculo estructural.
Las instancias comparten el banco, sin duplicar los maestros por habitación.

## Reproducción y comprobaciones

```sh
blender --background --python tools/lie28_prepare_blender.py -- \
  --materials /absolute/path/materials --resolution 128
python tools/lie28_verify_captures.py gpu_compute /absolute/path/materials
godot --headless --editor --path gpu_compute --import
python tools/lie_agent_launch.py --godot /absolute/path/godot \
  --project /absolute/path/Lie-Engine/gpu_compute --lab lie28 \
  --directory /absolute/path/fresh-session
python tools/lie28_agent_smoke.py --directory /absolute/path/fresh-session
```

El verificador independiente revisa SHA, finitud, normales, puntos en triángulos
fuente, color/rugosidad mediante PIL y UV interpoladas, huecos libres, superficies
de corte, cierre de las mallas, pertenencia a las celdas Voronoi y suma de volumen.
1,500 puntos de geometría y 1,188 de material comprobados. Error superficial
máximo: 0.0000004285 m; error de material máximo: 0.00002486. Diferencia de volumen
padre/fragmentos: 0.00000000003443 m³.

La prueba de escritorio pasó 119 comprobaciones con Vulkan real en llvmpipe:
renders de todos los
maestros, puerta/ventana transparentes, muro sólido encima de la puerta, cámara
desde varios ángulos, cubierta retirada, edición inválida atómica, revisiones,
guardar/restaurar imagen idéntica, cuatro fragmentos separados visibles,
separar/reunir fragmentos e identidad del
banco residente. No es una medición de velocidad de una GPU física o Android.
Los 72 tests Python existentes (uno omitido), las 888 comprobaciones de región/
rig y las 20 del protocolo de agente también se ejecutaron correctamente.

## Distribución

Identidades persistentes, tamaños y SHA exactos del paquete: `docs/checkpoints/LIE28_CHECKPOINT.json`.

Código, escenas, shader y generador en Git. `LIE28-Assets-Maestros.zip` contiene
GLB, Blender, mapas atribuidos, banco de capturas, oráculos y evidencia PNG.
No contiene el código del repositorio ni las fuentes de rostro de LIE-27.
Extraer sus carpetas `assets/lie28` y `captures/building28` dentro de
`gpu_compute/`; no hay que importar las mallas fuente al render de Lie.

Límites actuales: textura repetida, resolución de captura finita, fracturas
planas sin borde erosionado, ausencia de puertas/vidrios/mobiliario y de física
de construcción. Es una prueba funcional de maestros y ensamblaje modular,
no un constructor general de viviendas ni una casa terminada.
