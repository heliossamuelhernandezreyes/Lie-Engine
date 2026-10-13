# LIE CC0 Material Masters — primer lote (10 fuentes)

Este banco cataloga **materiales PBR de alta resolución** destinados al proceso de capturas offline de LIE. **No almacena un modelo 3D completo escaneado por material**, ni implica que el renderer actual genere imágenes idénticas a una foto. Las fuentes, mapas y licencias están separadas de `SpatialEnvelope` y de los bancos binarios `VisualSampleBank`.

## Selección

| Prioridad | ID | Fuente | Máximo listado | Resolución preferida |
| --- | --- | --- | --- | --- |
| 1 | `brick.hero.red_brick` | [Red Brick](https://polyhaven.com/a/red_brick) | 16K | 16K |
| 2 | `brick.clean.brick_wall_003` | [Brick Wall 003](https://polyhaven.com/a/brick_wall_003) | 8K | 8K |
| 3 | `brick.damaged.brick_wall_005` | [Brick Wall 005](https://polyhaven.com/a/brick_wall_005) | 8K | 8K |
| 4 | `concrete.hero.concrete_wall_008` | [Concrete Wall 008](https://polyhaven.com/a/concrete_wall_008) | 8K | 8K |
| 5 | `wood.hero.oak_wood_planks` | [Oak Wood Planks](https://polyhaven.com/a/oak_wood_planks) | 8K | 8K |
| 6 | `metal.hero.rusty_metal_sheet` | [Rusty Metal Sheet](https://polyhaven.com/a/rusty_metal_sheet) | 16K | 8K |
| 7 | `stone.hero.rock_08` | [Rock 08](https://polyhaven.com/a/rock_08) | 8K | 8K |
| 8 | `ground.hero.rocky_terrain` | [Rocky Terrain](https://polyhaven.com/a/rocky_terrain) | 8K | 8K |
| 9 | `asphalt.hero.asphalt_07` | [Asphalt 07](https://polyhaven.com/a/asphalt_07) | 16K | 8K |
| 10 | `plaster.hero.white_rough_plaster` | [White Rough Plaster](https://polyhaven.com/a/white_rough_plaster) | 8K | 8K |

Todas las fuentes son **Poly Haven, CC0 1.0**: https://polyhaven.com/license. La licencia permite comercialización y redistribución; aun así se conservan URL, autoría por proveedor y SHA-256 de cada descarga para reproducibilidad. Las resoluciones máximas son las visibles en sus páginas a la fecha de catalogación; la API decide qué mapas/formatos concretos están disponibles.

## Directorios

```text
assets/material_masters/
  catalog.json
  brick/
    hero/red_brick/material_manifest.json
    clean/brick_wall_003/material_manifest.json
    damaged/brick_wall_005/material_manifest.json
  concrete/hero/concrete_wall_008/material_manifest.json
  wood/hero/oak_wood_planks/material_manifest.json
  metal/hero/rusty_metal_sheet/material_manifest.json
  stone/hero/rock_08/material_manifest.json
  ground/hero/rocky_terrain/material_manifest.json
  asphalt/hero/asphalt_07/material_manifest.json
  plaster/hero/white_rough_plaster/material_manifest.json
  **/source/        # ignorado por Git: imágenes originales + source-lock.json
  **/derived/       # ignorado: transformaciones sin perder originales
  **/capture_bank/  # ignorado: salidas binarias pesadas de LIE
```

## Uso inmediato

```bash
python tools/lie_material_masters.py --list
python tools/lie_material_masters.py --download --id brick.hero.red_brick --resolution 8k
python tools/lie_material_masters.py --download --id brick.hero.red_brick --resolution 16k
python tools/lie_material_masters.py --download --all --resolution 4k
python -m unittest discover -s tests -p 'test_material_masters.py'
```

`--list` no descarga nada. Descargas únicamente mediante `--download` y `--id` o `--all`. La ruta local de cada mapa se guarda con SHA-256 en `source/source-lock.json`. La primera prueba a 4K/8K evita llenar el almacenamiento móvil accidentalmente; 16K es una fuente maestra para procesamiento offline, **no una textura runtime por ladrillo**. El código consume los mapas individuales con la API oficial (no descarga un GLB).

## Contrato LIE (no mezclar geometría con apariencia)

1. **Material de superficie:** albedo, normal GL, altura, rugosidad y AO opcional con dimensiones calibradas. Una imagen de muro con juntas de mortero **no equivale** a escanear un ladrillo por sus seis lados.
2. **Asset maestro geométrico offline:** para un ladrillo completo, se necesita modelado/escaneo 3D individual, aristas y caras laterales consistentes; aplicar mapas PBR y producir capturas de profundidad/normales/XYZ y múltiples puntos de vista. El antiguo `tools/lie_brick01_capture.py` ya transforma superficie fotográfica en muestras, pero no convierte ese material en un escaneo individual genuino.
3. **VisualSampleBank:** almacenar las muestras visuales capturadas y sus rangos de LOD. Referencias a un mismo master para muchas instancias; no duplicar 16K por ladrillo.
4. **SpatialEnvelope:** una caja invisible de límites por objeto y/o árbol de cajas por pared. La caja no se rasteriza como superficie visible. Una caja para culling no implica una sola operación GPU ni una colisión detallada perfecta.
5. **Validación:** frente, canto superior, perfiles, contraluz, sombras y compare A/B con fotografías; reportar falsos bordes, huecos, RAM, VRAM y coste del cómputo nativo. Nunca inferir equivalencia fotográfica de una prueba smoke.

## Integración futura

- El `tools/lie31_acquire_pbr.py` existente soporta el antiguo `red_brick` a 2/4/8K y su lock. Este banco no lo sustituye ni toca capturas previas.
- `tools/lie_material_masters.py` generaliza la adquisición CC0 **sin** modificar el renderizador ni producir assets maestros automáticamente. El siguiente paso es adaptar `tools/lie_brick01_capture.py` para leer estos locks y usar fuentes multivista geométricas reales cuando existan.
- Una alternativa individual escaneada disponible bajo **CC BY**, no CC0, es [Real brick photo scan, Sketchfab](https://sketchfab.com/3d-models/real-brick-photo-scan-ef1799f8b96d4cdfbc053e8c645dd042) (1.9k triángulos según ficha). No se incluye en este lote CC0 y no se ha adquirido; atribución y acceso a descarga deben verificarse independientemente.
