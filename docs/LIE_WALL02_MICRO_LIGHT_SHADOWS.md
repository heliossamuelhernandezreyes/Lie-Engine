# LIE-WALL-02 — micro-nodos del escaneo real y sombras directas por ladrillo

## RESULTADO VERIFICADO Y PUBLICADO — 2026-10-13

- **[Prueba GPU completa APROBADA](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38353380788):** Godot 4.7.2/Mesa Vulkan, resolución 1080×1080, 6 imágenes verdaderas; 865 nodos válidos y transporte LIE11 conservativo, luz neutra/cálida/fría, control de absorción y vista cercana.
- **[Publicación persistente APROBADA](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38353528878):** fuente auténtica CC BY, banco comprimido, SHA-256, modelo RGB y 6 imágenes en la rama experimental de GitHub. Restaurar con `python tools/lie_wall02_restore.py` sin necesidad de descargar el GLB original.
- **Banco de muestras 80 bytes**, 560.866 muestras, LOD cercano/intermedio/lejano **404.564 / 131.548 / 24.754**, SHA-256 `510cb9111da9fb8878f3a956288f3fe00c85a056a9e32397fe425c32ca4b0eb0`; origen original 500.000 triángulos / CC BY 4.0.
- **Modelo luminotécnico:** 865 nodos (864 de arcilla real, uno de mortero), 96 proxies GPU independientes solo para luz directa, **una caja invisible física**, 0 triángulos fuente dibujados. Código RGB numérico canonizado a precisión 1e-7 para evitar discrepancias de hash en distintos CPUs; SHA-256 `e5d911c89f9192f361fde626ac9cdd69552aebbfec766c30c24ec8cfab9b4e4e`.
- **Comparación aislada de sombras directas:** la misma luz rasante cálida, el mismo `shadows=true` de bloqueo de núcleo, exactamente la misma geometría: **56,09** luminancia media sRGB (proxies directos activos) contra **70,44** (solo los proxies directos desactivados). Así queda demostrado el consumo real del nuevo buffer de visibilidad GPU.
- **Captura cercana:** `evidence/LIE-WALL02-MicroLight-real_scan_closeup.png`. Se ven huecos negros, grano y juntas excesivamente oscuras. Resultado **funcional, no fotorrealista ni listo para producción**. Sin referencia fotográfica controlada, benchmark Android o ahorro de GPU certificado.
- **Error reproducible corregido:** la primera publicación encontraba un SHA diferente del JSON de nodos entre runners, aun con banco visual byte-a-byte idéntico. Los metadatos de promedios de nodo se cuantizan a 7 decimales antes de calcular SHA, sin modificar las muestras escaneadas.

---

## Qué corregimos de LIE-WALL-01

La pared LIE-WALL-01 ya dispone de **96 ladrillos realmente capturados**, un `VisualSampleBank` compartido y **una sola caja invisible** que representa la pared. Su luz viene de los códigos originales LIE-11: potencia RGB lineal, reflectancia/absorción, inyección en nodos y 2 rebotes conservadores. Sin embargo, cada ladrillo agrupaba una cara frontal entera en **un único nodo**; el bloqueo de luz también se aproximaba mediante **una sola caja interior para toda la pared**.

LIE-WALL-02 no cambia ese solver energético, la licencia ni la geometría visible original. Mejora la **precisión espacial de la entrada al solver**:

- **9 nodos por ladrillo**: 4 cuadrados de la superficie frontal Z+ y 5 regiones para las otras caras. En total, **864 nodos para ladrillos + 1 del mortero = 865** (dentro del límite LIE11 de 1024).
- Cada nodo deriva el **XYZ medio, normal media, color RGB lineal promedio** de las muestras capturadas del objeto auténtico (`COLOR_0`), trasladado y rotado en el aparejo de pared. Una perturbación de 1,5 mm coloca el punto de integración fuera de la superficie; es una aproximación de área.
- El **IDs de nodos** viaja dentro del mismo registro de 80 bytes por muestra LIE. Los 3 LOD siguen siendo un único maestro de pared y una instancia de GPU. **No se aumenta la cuenta de cajas de colisión.**
- **96 AABBs compactas, exclusivamente para visibilidad de luz directa**, cada una ligeramente contraída respecto al volumen escaneado. El GPU excluye la caja del ladrillo que recibe la luz para evitar autooclusiones de la piel irregular. Las cajas no existen como `CollisionShape3D`, no se dibujan y no sustituyen la forma real.
- El transporte **sigue siendo el LIE11 original**: mismo peso inverso al cuadrado, límites y radio, reflectancias, material code/absorción, matriz recíproca de transferencia y dos generaciones de rebote. Su shader recibe una ampliación *opcional* en `binding=17` para visibilidad del rayo directo.
- La oclusión de **rebotes indirectos** continúa usando la aproximación conservadora del núcleo de la pared anterior, **no** las 96 cajas. No afirmar sombras exactas por triángulo ni microoclusiones físicas.

## Flujo nuevo

```text
Scan real Stratford Brick (500k triángulos; CC BY 4.0)
       │ Fuente de verdad: XYZ + normales + COLOR_0 lineal
       ↓
VisualSampleBank: 96 ladrillos escaneados · muestras 3 LOD
       ├─ sample.attributes.y → nodo 0..864 (mortar 864)
       ├─ 1 instancia visual + 1 caja invisible gruesa de la pared
       │
       └─ LightingNodeField 865 patches → original LIE11 GPU
                  │            96 light-only AABB blockers (binding 17)
                  │            sin mallas ni colisionadores nuevos
                  ↓            luz RGB directa + rebotes
           GPU RGBA32F irradiancia nodal + buffer de códigos
                  ↓
           LIE33 sample compositor (sin segunda luz puntual ni ambiente)
                  ↓
           Captura 1080 × 1080 original Godot Vulkan
```

## Reproducción (la fuente CC BY ya está publicada)

```bash
python -m pip install numpy pillow
python tools/lie_brick02_restore.py
python tools/lie_wall01_bake.py --output gpu_compute/captures/liewall02
python -m unittest discover -s tests -p 'test_lie_wall02_micro.py' -v
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab liewall02 \
  --directory /tmp/lie-wall02-native
python tools/lie_wall02_native_smoke.py --directory /tmp/lie-wall02-native
```

El laboratorio permite cambiar de luz neutra, cálida y fría, absorción de arcilla y cámara. **El nuevo interruptor `direct_shadow_proxies` activa/desactiva *solo* los 96 proxies de luz directa**, manteniendo constante `shadows=true`, la luz y el bloqueador del núcleo. Así una pareja de capturas constituye una prueba aislada del nuevo sistema.

## Presupuestos y limitaciones

- LIE11 usa una matriz **densa**: 865² = 748.225 relaciones, frente a 577² = 332.929. La complejidad de rebotes y compilación de factores aumenta aproximadamente 2,25×, aunque la memoria de la matriz float32 sigue rondando 3 MiB; debe medirse en hardware Android.
- La fase de luz directa inspecciona hasta 865 × 96 = 83.040 posibles intersecciones de rayo-AABB cuando hay una luz. Se repite al cambiar un código de fuente/sombras; **no** se convierte en 96 instancias de renderización.
- Los nodos subdivididos **no producen fotogrametría adicional**: las muestras y normal de la fuente original ya existían. No se generan triángulos ni nuevos detalles que el escaneo no contenga.
- El objeto está digitalizado por un autor bajo **CC BY 4.0**, no CC0. Mantener atribución Centre-of-Archaeology y enlace original en cualquier distribución/obra derivada.
- **Ausentes todavía:** sombreado especular conservador, rayos contra cada muestra/triángulo, interpolación continua entre los cuatro nodos de una misma cara, mortero fotografiado, cierre de extremos con ladrillos cortados, FPS/memoria en GPU física y comparación A/B de fotografías de una pared real.
- El código fuente es un experimento separado de LIE-WALL-01, y no debe fusionarse a producción sin revisión visual.

## Evidencia

El flujo [LIE-WALL02 native micro-light](../.github/workflows/lie-wall02-micro.yml) contrasta el solve de luz con referencia Python, comprueba los 865 nodos, la identificación de la fuente escaneada y los 96 proxies. Las capturas nativas prueban luz RGB/absorción y diferencia de sombras **con la misma fuente y conmutando únicamente el buffer de visibilidad directa**. La validez del resultado final depende de que GitHub Actions informe `success`.
