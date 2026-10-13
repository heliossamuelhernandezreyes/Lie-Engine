# LIE-WALL-03 — continuidad de muestras, mortero RGB por hilada y medición

## Objetivo

Continuar la **pared LIE-WALL-02**, no construir una pared convencional de polígonos. Se conserva el original `Stratford New Place Brick Ver 2` (Centre-of-Archaeology, licencia **CC BY 4.0**), 500.000 triángulos en el archivo offline, colores `COLOR_0` lineales, **96 ladrillos capturados**, tres LOD de **404.564 / 131.548 / 24.754 muestras**, una sola instancia visual y **una sola caja invisible** para la pared completa. En ejecución no se dibujan los triángulos originales.

## Hallazgos previos en capturas reales

La inspección de la imagen cercana de LIE-WALL-02 encontró dos problemas independientes:

1. **Cobertura incompleta de muestras escaneadas**: pequeños huecos interiores, aliasing y pérdida de continuidad entre splats (muestras de superficies verdaderas).
2. **Juntas demasiado oscuras**: el modelo anterior usaba un patch RGB único para todo el mortero. Inicialmente este mortero quedó **11 mm hundido**, mientras los 96 proxies conservadores de luz se situaban dentro del volumen de ladrillo; los rayos hacia esa superficie quedaban muy bloqueados. No debe corregirse inventando un término de luz ambiente o modificando el albedo real de los ladrillos.

## Implementación LIE-WALL-03

### A. Reparación segura de huecos interiores (GPU Vulkan)

- `shaders/lie_wall03_coverage.glsl` añade la etapa **8** después de iluminación y combinación de muestras, antes del downsample final. Reutiliza `specular_image` como scratch **después** de que el estadio 6 ya consumió su valor previo. No se asigna otro render target.
- El shader compara **sólo** píxeles que ya son fuentes válidas y pertenecen al **mismo ladrillo** (`sample.attributes.y / 9`), con normales compatibles (producto punto > 0,65), diferencia de profundidad inferior a los umbrales y test de vecinos opuestos. El relleno exige **mínimo tres vecinos de la misma superficie agrupada**, a ambos lados en X o Y.
- La reconstrucción copia la radiancia *ya calculada por los códigos RGB originales de LIE-11*, no dibuja material inventado ni una textura de seis caras. No debe extender siluetas ni mezclar píxeles de ladrillos distintos.
- `coverage_enabled` en el laboratorio permite un A/B bajo idéntica cámara/iluminación. En modo OFF la etapa 8 se limita a copiar valores, manteniendo la misma cadena de GPU para comparabilidad.

### B. Mortero físicamente separado, codificado por hiladas

- La geometría visible del escaneo auténtico **no se altera ni un solo byte**. Sólo cambia el mortero explícitamente **procedimental**.
- Ocho nodos finitos (uno por hilada) sustituyen el patch único de mortero. Con los nueve nodos por cada ladrillo escaneado, el modelo suma **872 nodos**, por debajo del límite de 1024 de LIE-11.
- El mortero ahora está hundido **3,5 mm** respecto al frente nominal del ladrillo. Es más superficial que la versión de 11 mm, pero todavía recesado; se sitúa fuera de los AABB interiores de sombras.
- Los rayos que atraviesan **zonas nominales de junta** pueden completarse mediante una máscara espacial basada en el aparejo real (no un plano de textura que tape la geometría). Su color se calcula como **albedo procedural de mortero × energía RGB lineal del patch de LIE-11**.
- Para cada pixel, el shader primero rechaza el interior de los `96` footprints de ladrillo. La única caja `SpatialEnvelope` continúa usándose **solo para ubicación y colisión gruesa**, no como superficie visible ni como cálculo del mortero.

### C. Iluminación

- LIE-11 sigue siendo la fuente de verdad de energía: radiación directa, absorción `absorption_code`, RGB lineal y dos rebotes conservadores. Se mantienen los 96 proxies **exclusivamente luminotécnicos**, no 96 colisionadores.
- **No** se ha añadido un shader puntual independiente, ambient fake, GGX doble ni nueva geometría; el shader de huecos y juntas lee los buffers existentes del mismo transporte GPU.

## Validación y reproducción

```bash
python -m pip install numpy pillow
python tools/lie_brick02_restore.py
python tools/lie_wall03_bake.py --output gpu_compute/captures/liewall03
python -m unittest discover -s tests -p 'test_lie_wall03_coverage.py' -v
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /ruta/godot --lab liewall03 --directory /tmp/lie-wall03
python tools/lie_wall03_native_smoke.py --directory /tmp/lie-wall03
python tools/lie_wall03_benchmark.py --directory /tmp/lie-wall03 --poses 5
```

Capturas oficiales Godot/Vulkan: `LIE-WALL03-SameLight-CoverageOFF.png`, `LIE-WALL03-SameLight-CoverageON.png`, `WarmRaking`, `CoolLight` y `ClayAbsorption60`.

### Métricas del A/B inicial

A 1080 × 1080, con igual cámara e iluminación neutra, el **primer relleno sólo de huecos** pasó de **350.965** a **362.990** píxeles visibles (+12.025; +3,4%). Luego la corrección de profundidad del mortero modificó la máscara y el albedo visibles: esa comparación no debe interpretarse como una ganancia del algoritmo de cobertura por sí solo. Se requiere el último reporte `LIE-WALL03-native-validation.json` para la comparación estricta de cada revisión.

La corrección luminotécnica del mortero redujo los píxeles visibles prácticamente negros respecto al mortero de 11 mm. La mejora visual es real, pero las juntas horizontales todavía pueden permanecer en sombra.

### Medición de rendimiento sin afirmaciones inventadas

- `lie_wall03_benchmark.py`: el mismo banco, resolución, poses, materiales y luces; alterna cobertura OFF/ON en cuatro rondas y registra GPU timestamps de Godot si están disponibles.
- GitHub Actions utiliza **Mesa Vulkan en CPU (llvmpipe)**. Esto **NO** mide FPS del teléfono ni demuestra que LIE vaya más rápido que un motor rasterizado. No extrapolar los tiempos del emulador a GPUs móviles.
- El compositor existente a resolución interna 2160 × 2160 es costoso: asigna aproximadamente **495 MiB** de recursos GPU en la validación Mesa. LIE-WALL-03 añade sólo **48 bytes** de configuración de juntas; su etapa extra de cobertura tiene coste de cómputo, y se debe medir con la GPU objetivo.
- Para medir correctamente en Android físico: utilizar Godot Vulkan/RenderingDevice en un build nativo, ejecutar las mismas cuatro rondas y registrar `gpu_ms`, CPU, RSS/PSS y estabilidad de frames sin suponer que los tiempos de Mesa equivalen a FPS.

## Límites de calidad

**No está certificado como fotorrealista.** Persisten aliasing, huecos demasiado grandes para la máscara limitada, irregularidad de juntas, diferencias de color y sombras aproximadas de AABB, no de triángulos originales. Las superficies del mismo ladrillo todavía reutilizan un único escaneo y falta variar verdaderos bricks individuales, mortero fotografiado, sombras por muestra y comparación A/B con fotos de un muro físico. Mantener atribución CC BY al redistribuir.

Toda publicación de LIE-WALL-03 debe conservar el SHA-256 de fuente, el banco de 80 bytes por muestra, 96 bricks, un envelope, 872 nodos de material/luz y el resultado negativo del problema de mortero de 11 mm.
