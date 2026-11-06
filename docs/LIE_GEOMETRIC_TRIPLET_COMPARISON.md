# Comparador de tres etapas para diagnosticar geometría — LIE

**Estado:** infraestructura de análisis CPU, no es una ejecución de Vulkan ni una modificación al renderizador. Se agregó a la rama de investigación del PR #73.

## Por qué existe

Para una misma cámara, pose, resolución y convención de profundidad (lineal, en metros), distingue:

1. `source`: geometría fuente original, raycast o superficie analítica.
2. `representation`: geometría que la captura/compilación de LIE efectivamente representa, consultada por un oráculo independiente.
3. `consumer`: resultado renderizado/consultado por el consumidor (en las demos, **emulador CPU**, no la GPU de LIE).

Compara fuente→representación y representación→consumidor; así no se culpa al shader por un relieve que jamás se capturó.

## Ejecución

```bash
python -m unittest discover -s tests -p 'test_lie_geometric_triplet_compare.py' -v
python tools/lie_geometric_triplet_compare.py --demo wall_hole --output /tmp/lie-wall-triplet.json
python tools/lie_geometric_triplet_compare.py --demo hidden_bump --pixel-causes --output /tmp/lie-bump-pixels.json
python tools/lie_geometric_triplet_compare.py --input captured-triplet.json --output /tmp/captured-diff.json
```

Los `--demo` reutilizan únicamente las superficies analíticas y parches CPU del experimento previo. **No verifican el shader ni el teléfono.**

## Formato de datos

Por cada capa: `hit` (0 o 1), `depth_m` (profundidad finita en metros donde hay impacto, y `null` si no hay), y opcional `owner_id`. Todos son arreglos planos fila-major de longitud `width * height`. Ejemplo mínimo:

```json
{
  "schema": "lie-geometric-triplet/1",
  "width": 2,
  "height": 1,
  "depth_tolerance_m": 0.005,
  "provenance": {"camera": "pose-test-01", "depth_convention": "linear-z-m"},
  "layers": {
    "source": {"hit": [1, 1], "depth_m": [0.4, 0.5]},
    "representation": {"hit": [1, 0], "depth_m": [0.4, null], "owner_id": [100, null]},
    "consumer": {"hit": [1, 0], "depth_m": [0.4, null], "owner_id": [100, null]}
  }
}
```

El productor de los datos **debe** alinear las capas con idénticas matrices, poses, resolución, near/far, convención de profundidad, escala de coordenadas y hashes. El comparador no puede detectar automáticamente una matriz de cámara equivocada.

## Métricas y precauciones

Para cada par: faltantes, sobrantes, IoU, errores de profundidad mayores que la tolerancia, error absoluto p50/p95/p99/máximo en píxeles con dos impactos, y errores de propietario **solo cuando ambos IDs son comparables**. El resultado `owner_mismatches: null` significa no disponible, **no** cero errores.

Clasificación por píxel:
- `data_only`: fuente y representación difieren, consumidor coincide con representación.
- `consumer_only`: representación y consumidor difieren, fuente coincide con representación.
- `both`: ambas comparaciones difieren; causa única **no establecida**.
- `neither`: sin discrepancias detectables con este contrato.

`--pixel-causes` emite etiquetas por píxel para posteriores superposiciones. Sin esa opción genera un resumen compacto.

No compara iluminación, sombras, textura, RGB, oclusión temporal ni fidelidad desde cámaras no ensayadas. Tampoco demuestra que falten datos en las capturas *reales* de LIE.

## Siguiente discriminador real

En la pared de LIE 2.5, usar la pose fallida guardada (yaw -72.90939846038818°, elevación 2.0563994513617607°, distancia 0.6, 720 × 720). Exportar tres capas **realmente alineadas**: raycast de la fuente Blender, oráculo de la representación almacenada y readback Vulkan de primer impacto/propietario/profundidad. Repetir a yaw ±0.1°, luz deshabilitada; revisar apariencia solo cuando la geometría esté protegida.

**Advertencia:** el método `regions` no es sinónimo de verdad original Blender. Si los assets fuente no están disponibles, documentar la carencia y no inventar una comparación.

**Decisión:** mantener esta prueba y las demás en rama de investigación; no fusionar ni sustituir LIE sin evidencia GPU + fuente real.
