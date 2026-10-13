# LIE-WALL-01 — pared de ladrillos escaneados + iluminación RGB original de LIE-11

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
