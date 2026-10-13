# LIE-WALL-01 — pared de ladrillos escaneados + iluminación RGB original de LIE-11

## RESULTADO VERIFICADO — pared de ladrillo real y códigos LIE11 (2026-10-13)

- **Fuente real:** 500.000 triángulos y 357.956 vértices, `Stratford New Place Brick Ver 2`, Centre-of-Archaeology, CC BY 4.0, fuente conservada en `lie_brick02/source_provenance.json`.
- **Un solo maestro visual de pared:** 96 ladrillos reales capturados y transformados de forma reproducible, **una sola instancia del compositor**, **una caja invisible** `BoxShape3D` de dimensiones **2,64675 × 0,68788 × 0,12862 m**; **0 triángulos fuente dibujados**.
- **Muestras LIE:** **560.866** muestras reales/procedurales (ladrillos de fuente real y mortero separado), 3 LOD **404.564 / 131.548 / 24.754**, stride 80 B, SHA-256 `9446ac800318cc1967b09f8f1c59ddde3d76c95e877705e4f95a364e29d0c031`.
- **Iluminación:** **577 nodos físicos codificados** (6 patches por ladrillo + un patch común de mortero), RGB lineal, absorción dinámica y 2 rebotes conservadores del solver **original LIE11 GPU**. Shader del compositor enlazado al buffer/imagen del mismo transportador.
- **Pruebas:** [workflow real de Mesa Vulkan 1080² aprobado](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38351515530), 4 PNG originales; laboratorio acepta 3 colores de luz y absorción. Referencia independiente Python confirmó invariantes conservadores del campo de 577 patches.
- **Fuente de verdad persistente:** [GitHub publish workflow completado](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38351765810), banco comprimido `gpu_compute/assets/lie_wall01/wall_bank.zlib`, luz `light-model.json`, catálogo y atribución, imágenes en `evidence/LIE-WALL01-RealScan-*.png`.
- **Reproducir sin volver a descargar el escaneo:** `python tools/lie_wall01_restore.py`, luego cargar `gpu_compute/lie_wall01_coded_lab.tscn`.

### Hallazgo visual negativo preservado

La **v1** de pared trató el mortero como un plano completo detrás de las caras sobresalientes del ladrillo, pero no detrás de sus cavidades más profundas. Una parte del modelo escaneado quedaba oculta por el plano y la pared mostraba **cuñas triangulares**, aun cuando el transporte RGB y los hashes eran correctos. Es una prueba de por qué la aceptación visual debe ser independiente de las pruebas de geometría/datos.

La **v2** corrigió la máscara: genera mortero **sólo en las juntas entre footprints nominales** y no dentro de los recintos XY de cada ladrillo; el escaneo completo deja de quedar tapado. Lo demuestran las capturas del run `38351515530`. Conserva bordes escalonados abiertos por el aparejo corrido, aliasing/ruido residual y juntas oscuras. **No se aprueba aún como fotorrealista.**

### Comparación controlada de inyección luminosa (v2)

| Escenario original Godot/Vulkan | Luminancia media de píxeles ocupados (sRGB 0–255) |
| --- | ---: |
| RGB neutro | 84,18 |
| Luz cálida rasante | 65,47 |
| Luz fría lateral | 72,33 |
| Luz fría con absorción 60% | 53,12 |

La modificación de absorción disminuyó la luminancia sin recapturar el asset, con **4 actualizaciones de códigos** registradas; estos valores son métricas de imagen, **no vatios** ni medidas de GPU física. Luces y poses difieren entre las primeras tres escenas, por lo que no se interpreta su luminancia como un test de conservación de energía; esa invariancia se comprueba por separado en el solver.

**Deuda de calidad:** sombras por patches medios, sin oclusión fina de cada triángulo o muestra; especular desactivado para evitar doble contabilización; mortero procedimental, ausencia de bricks partidos, sin referencia fotográfica A/B y sin benchmarks de GPU Android.

---

## Auditoría del código existente (antes de modificar)

LIE **sí** incluye iluminación mediante códigos de material y luz por nodos; está implementada y descrita en [LIE-11](LIE_11_CODE_LIGHTING.md) y [LIE-12](LIE_12_CAPTURE_CODE_LIGHTING.md), **pero no estaba conectada al LIE33 usado por LIE-BRICK-02**.

| Versión | Qué hace realmente | Evidencia en fuente |
| --- | --- | --- |
| LIE-11 | Un nodo/patch tiene XYZ, normal unitaria, área, reflectancia gris, filtro RGB y código de absorción. Una luz inyecta potencia RGB lineal; GPU Vulkan calcula emisión directa, factores recíprocos y 0–8 rebotes. | `lie11_model.gd`, `lie11_light_effect.gd`, `shaders/lie11_light_transport.glsl` |
| LIE-12 | Asocia pixeles capturados a nodos y usa imagen de irradiancia de LIE11 en un compositor de reconstrucción. No usa geometría visual fuente en runtime. | `shaders/lie12_pipeline.glsl`, `docs/LIE_12_CAPTURE_CODE_LIGHTING.md` |
| LIE-33 (antes) | Recibe RGB lineal de las muestras, calcula en *otro shader* una luz puntual, sombra de mapa 512², término de ambiente y GGX. No consumía `LIE11.output_rid`; por tanto el brick escaneado **no estaba usando los códigos LIE11**. | `shaders/lie33_tiled_brick.glsl` etapas 4/6, `lie_brick01_lab.gd` |

### Radiometría que preservamos

De LIE11: `rho_i = gray_mean_i × tint_linear_i × (1 − absorption_code_i/1000)`. La irradiancia lineal acumulada de cada patch es `E_i = received_power_i / area_i` con suma conservadora de luz directa + generaciones secundarias (solo la generación inmediatamente anterior alimenta el siguiente rebote). Los pesos primarios se suavizan a 5 cm, se limitan por radio con `(max(0,1−(d/r)^4))²` y se normalizan para no aumentar la potencia fuente. El grafo de factores difusos usa corrección simétrica local para reciprocidad y sumas de fila ≤ 1. Este modelo es **aproximado de patches finitos**, no path tracing ni solución espectral exacta.

El consumidor nuevo lee **en GPU** `E_i` y el código dinámico de absorción del mismo patch. Por muestra/pixel su aporte difuso es:

`L_RGB = color_original_LINEAL_RGB × (1 − absorption_node) × E_node / π`.

**No añade luz puntual, especular GGX ni constante ambiente de LIE33** al usar este modo. Así no se contabiliza energía dos veces. La componente especular física queda pendiente de auditoría separada.

### Integración real

```text
Stratford New Place Brick real CC BY (500K triángulos)
    ↓ [captura OFFLINE de superficies XYZ y COLOR_0 LINEAL]
VisualSampleBank autenticado SHA-256 · LIE-BRICK-02
    ↓ [recolocación determinista de muestras + mortero separado]
WallSampleBank: 96 ladrillos, 3 LOD, 1 instancia GPU por pared
    │                       └─ 1 SpatialEnvelope invisible de toda la pared
    └─ sample.attributes.y → patch_id 0..576
          ↓
LightingNodeModel: 96 × 6 patches (normales±XYZ, áreas) + 1 mortero
    ↓
lie11_light_effect.gd (PRE_OPAQUE; GPU)
    ├── output_rid: RGBA32F irradiancia de cada patch
    └── material_codes_rid: absorción/filtro sin duplicar modelo
                 ↓ [bindings 14/15; sin readback]
lie_wall01_coded_effect.gd (POST_TRANSPARENT; GPU)
    ↓
lie_wall01_coded.glsl: muestra escaneada × irradiancia nodal
    ↓
Imagen 1080 × 1080 + alpha para compositor
```

- **Una caja invisible** `BoxShape3D` con `bounds_center`/ `bounds_size` de la pared completa. Es *colisión gruesa* y *culling espacial*, **no los triángulos de la apariencia**. No se crean 96 colisionadores.
- El mortero es un plano superficial **sintético y rehundido** para hacer visibles juntas, no parte del escaneo real. Documentado en catálogo.
- Cada ladrillo hereda la muestra auténtica RGB/XYZ, con semilla estable, variación tonal y yaw leve. Repetir un maestro no es escanear 96 ladrillos distintos. El layout deja extremos escalonados y no genera mitades originales.
- El banco contiene 3 rangos LOD; copiar un maestro de ladrillo 96 veces directamente violaría el presupuesto GPU. El bake reduce muestras conservando representaciones reales.
- `light-model.json` es un banco de nodos *separado* de `library.bin`. Cambiar potencia, tono o absorción **no** necesita recapturar los 96 objetos.
- `LightTransport.set_light_codes` actualiza sólo el buffer persistente de luces; `set_material_codes` modifica sólo los códigos de material. Ambas actualizaciones conservan el grafo de visibilidad y la geometría cuando el layout no cambia.
- Los puntos consumen la **irradiancia emitida por LIE11** directamente. No se inventó un segundo solver ni se guardaron imágenes de iluminación prerenderizadas como sustituto.

## Cómo reproducir (fuente real ya guardada en GitHub)

```bash
python -m pip install numpy pillow
python tools/lie_brick02_restore.py
python tools/lie_wall01_bake.py
python -m unittest discover -s tests -p 'test_lie_wall01_coded.py' -v
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /path/to/godot --lab liewall01 \
 --directory /tmp/lie-wall01-agent
python tools/lie_wall01_native_smoke.py --directory /tmp/lie-wall01-agent
```

El laboratorio permite tres códigos RGB reales: **neutral**, **cálido rasante**, **frío lateral**; además, luz móvil por azimut, potencia, **absorción de arcilla** y activación/desactivación de la obstrucción aproximada del núcleo de la pared.

## Validación y límites explícitos

- Los test comprueban fuente escaneada SHA-256 y números de triángulos originales, cero triángulos fuente dibujados, bounds y una caja, rangos de muestras, IDs de patches coherentes, conservación/reciprocidad del solver independiente.
- El native smoke verificará **capturas originales** Godot/Vulkan a tres iluminaciones y cambio de absorción con distinta imagen y menor luminancia, más LOD lejano.
- La interacción entre nodos utiliza **normales medias de seis regiones por ladrillo**, no normales/visibilidad por cada muestra o ray tracing de los 500.000 triángulos. Una caja interna opaca de pared representa bloqueo aproximado, no sombras geométricas perfectas. Diferentes superficies cercanas pueden tener errores.
- El `VisualSampleBank` guarda color de vértice del escaneo (`COLOR_0` glTF lineal), **no** mapas de color UV.
- La calidad no se presume indistinguible de fotografías. Deben medirse paridad de silueta/color, aliasing, coste de GPU real, consumo de energía, overhead de grafo N² y memoria móvil.
- Licencia obligatoria **CC BY 4.0**, autor Centre-of-Archaeology, fuente Sketchfab original; mantener atribución en todo producto derivado.

### Continuaciones (no incluidas en v1)

1. Nodos de iluminación distribuidos adaptativamente a microzonas y BVH proxy de la auténtica pared para evitar fugas y resolver contactos.
2. Parches de radiancia especular calibrada para arcilla real con Fresnel sin introducir energía neta artificial.
3. Mitades reales, rotura/destrucción LOD reversible y sistema de culling de hijos al activar interacción.
4. Comparación visual con fotografías físicas y benchmarks en dispositivos Android/PC con GPU real.
