# Banco LIE de materiales fotográficos de alta resolución · v4

La calidad de la fuente es el requisito por defecto. Los ocho maestros simples
del kit v3 continúan identificados como prototipos funcionales. No constituyen
el estándar visual ni se reclasifican como capturas de alta calidad.

## Fuentes incorporadas

Originales de Poly Haven, CC0 1.0. **Powered by Poly Haven**.
Todos los mapas seleccionados son originales de 8192 × 8192, sin reescalado.
Se conservan sus bytes y se fijan URL, tamaño, MD5 del proveedor y SHA-256.

| Material | Fuente física completa | Aplicación | Relieve del archivo Blender |
|---|---:|---|---:|
| [Concrete Layers](https://polyhaven.com/a/concrete_layers) · Amal Kumar | 1.55 × 1.55 m | Superficie de concreto, revestimientos | escala 0.045 m, centro 0.5 |
| [Wood Table Worn](https://polyhaven.com/a/wood_table_worn) · Dimitrios Savva / Rico Cilliers | 0.55 × 0.55 m | Madera desgastada, paneles | escala 0.001 m, centro 0.37 |
| [Rock Boulder Dry](https://polyhaven.com/a/rock_boulder_dry) · Dimitrios Savva / Rico Cilliers | 1.80 × 1.80 m | Superficie pétrea, revestimientos | escala 0.085 m, centro 0.5 |
| [Grey Plaster](https://polyhaven.com/a/grey_plaster) · Rob Tuytel | 1.00 × 1.00 m | Revoco gris | escala 0.007 m, centro 0.65 |

Las dimensiones XY proceden de los metadatos del proveedor. Los parámetros Z
proceden de sus nodos de desplazamiento en Blender; no equivalen a una
certificación metrológica de profundidad. El revoco no se declara mortero:
su composición no está verificada. La textura de roca no es una roca completa
escaneada. Una superficie fotografiada y un objeto completo son fuentes distintas.

## Qué está capturado

Cada material aporta un parche central de **32 × 32 cm**, con una malla fuente
de **2,097,152 triángulos** construida a partir del mapa de altura de 16 bits.
La malla se usa fuera de línea; el render nativo dibuja únicamente muestras LIE.
No hay caras laterales ni reverso inventados. El recorte central no se declara
repetible sin costura; no debe multiplicarse en un muro como si fuera un atlas
perfectamente continuo. Se conserva el material completo para nuevas extracciones.

El compilador compartido recibe una declaración explícita de escala, pivote,
orientación X derecha / Y arriba / Z frente, procedencia y material opaco.
Captura color lineal y rugosidad mediante UV bilineales directamente desde
los EXR originales. El relieve y sus normales geométricas se obtienen del
mapa de altura, sin confundirlo con las normales ópticas.

La altura RGB16 de la piedra necesita OpenImageIO: Pillow la convertiría
silenciosamente a RGB de 8 bits. Las otras alturas son PNG escalares de 16 bits.
Algunos EXR del proveedor usan compresión DWAA, que puede introducir mínimos
valores fuera de [0,1]. Se conservan intactos; se limita explícitamente a [0,1]
el material opaco derivado. No se afirma que todos los EXR sean sin pérdida.

Cada banco contiene 512,000 / 128,000 / 32,000 muestras en tres LOD,
**53,760,000 bytes**, por debajo del límite de 64 MiB del consumidor actual.
Los cuatro bancos suman **215,040,000 bytes**. El laboratorio cambia de banco
por material; no implica render simultáneo de cuatro materiales con un único
consumidor. Dos consumidores del mismo banco comparten el buffer inmutable.
El conjunto de cuatro paneles reutiliza el mismo maestro con giros rígidos.

## Límites explícitos de calidad

Los mapas originales de normales ópticas se archivan con sus hashes. El formato
80B actual todavía no los consume. No se introducen como normales geométricas,
pues cambiarían indebidamente visibilidad y profundidad. Las capturas conservan
color, rugosidad y relieve geométrico, pero todavía pierden parte del microdetalle
óptico de las fuentes. El shader GGX actual mantiene F0=0.025 y su propio ambiente;
no constituye una reproducción completa del material original ni GI compartida.

Una fuente de 8K no convierte una captura LIE en una imagen de 8K. Las imágenes
nativas se obtienen a **1024 × 1024**, con reconstrucción interna a 2048 × 2048.
La densidad de muestras y los LOD limitan el detalle. La referencia independiente
compara el modelo opaco que el backend consume: altura, color y rugosidad, con
normales geométricas. No certifica equivalencia con el material PBR completo que
incluye el mapa normal. No se declara certificación hero ni rendimiento Android.

## Reproducción

Godot **4.7.2**, Python 3.12 y `requirements-hq.txt`.

```bash
python -m pip install -r requirements-hq.txt
python tools/lie_hq_materials.py --acquire --sources /tmp/hq/sources --output /tmp/hq/banks
python tools/lie_hq_stage.py --banks /tmp/hq/banks --stage /tmp/hq/stage
godot --headless --path /tmp/hq/stage --editor --import --quit
godot --path /tmp/hq/stage --rendering-driver vulkan --rendering-method mobile --script res://test_lie_hq_materials.gd
python tools/lie_hq_verify.py --sources /tmp/hq/sources --stage /tmp/hq/stage --output /tmp/hq/evidence
```

El bloqueo está en `gpu_compute/assets/hq_materials/sources.lock.json`. Los
originales, bancos y evidencias voluminosos se distribuyen aparte del código.
El archivo Blender del proveedor se conserva por procedencia y parámetros;
sus rutas de textura originales no se reescriben. El importador explícito usa
los nombres archivados y los hashes de la declaración de superficie.

## Validación requerida

- Regresiones CPU del proyecto y pruebas de UV, fotometría, relieve y rechazo de manipulación.
- Importación nativa, cobertura, profundidad, valores finitos, dos ángulos oblicuos,
  cambio de luz, tres LOD, conjunto rígido, restauración determinista y ciclo de vida
  del banco compartido.
- Comparación independiente por rayos contra la superficie fuente: cobertura
  interior, error RGB y error de profundidad. Sus resultados se conservan, sin
  confundir la aceptación numérica con una certificación hiperrealista.

Fuentes técnicas: [estándar de texturas](https://docs.polyhaven.com/en/technical-standards/textures),
[licencia](https://polyhaven.com/license). La calidad de las fuentes se conserva;
la siguiente ampliación del backend debe añadir normales ópticas separadas y
extracción continua de regiones antes de usar estos recortes como superficies
extensas de casas.
