# Auditoría de suficiencia geométrica de LIE — 2026-11-04

**Estado:** auditoría estática y de evidencia registrada; **no** constituye una nueva ejecución en GPU, una validación visual completa, ni la aprobación de un renderizador.  
**Ámbito:** `main` en `7845c3e7170eb4496a242f7c09b5df0ba44a4924` (laboratorios LIE-14/16/22/26/27) y experimentos independientes `work/lie-native-depth` / LIE 2.5. **No confundir estas dos líneas ni afirmar que la segunda está integrada en `main`.**

## Pregunta y veredicto

¿La información que ya conserva LIE basta para determinar qué superficie debería verse desde cualquier cámara y pose admisibles, antes de discutir FPS?

**Veredicto verificable:** LIE conserva suficiente estructura espacial para transformar muestras, reutilizar maestros, asignar propietarios, animar ciertos tejidos y reconstruir imágenes en numerosos casos protegidos. **No está demostrada la suficiencia geométrica global** de sus capturas para visibilidad exacta desde cualquier cámara/pose; hay contraejemplos observados en cámaras concretas y faltan contratos de cobertura, conectividad y disoclusión para objetos arbitrarios. La separación entre geometría invisible y apariencia **ya existe**; no corresponde reemplazarla sin una prueba causal.

Distinguir tres afirmaciones diferentes:

1. **Información:** ¿existe en el activo alguna descripción suficiente de la superficie real a consultar?
2. **Consulta:** si existe, ¿el algoritmo encuentra el primer impacto, con ID y profundidad correctos?
3. **Apariencia:** dado el impacto correcto, ¿normal/material/sombra/iluminación generan el color esperado?

Un error en (2) no prueba necesariamente que falten datos en (1). Un defecto de iluminación en (3) no debe clasificarse como hueco geométrico.

## Inventario comprobado en código

| Familia | Contrato presente | Qué NO garantiza |
| --- | --- | --- |
| LIE-14 rígido | Caja invisible para descarte; maestro de capturas con XYZ, normales y profundidad; cilindro analítico para determinadas consultas de sombras | La caja no describe la superficie visible ni su primera intersección. El cilindro analítico no es un resolvedor general de superficies capturadas |
| LIE-16 muestras rígidas | Proyección de muestras, huellas, profundidad sobre plano local, ganadores y mezcla condicionada por superficie/normal/identidad | Continuidad exacta entre muestras, conectividad global, visibilidad correcta en regiones nunca observadas |
| LIE-22 pared modular | Maestros capturados reutilizables, identidad de ladrillo, región/celda de material, partes internas precapturadas y física con colliders invisibles | Cortes arbitrarios, superficies interiores no capturadas o garantía global de primeras intersecciones |
| LIE-26/27 anatomía | XYZ capturado, normales, radios, materiales, 45 huesos en LIE-27, cápsulas/regiones invisibles y un subconjunto de vínculos baricéntricos triangulares para deformar o limitar muestras | Triangulación renderizable completa de toda la piel; cobertura exacta para toda pose; constitución cerrada/continua de todos los tejidos; física de personaje completa |
| LIE 2.5 vistas (`work/lie-native-depth`) | 64 vistas ortográficas derivadas para cada maestro, profundidad y procedencia, tres candidatas y refinamiento de profundidad del campo original | Información de parallax/disoclusión exacta en todas las cámaras; las capturas de ángulo finito no son un resolvedor universal |
| Experimento native-cell (`work/lie-native-depth`) | Láminas finitas de celda con profundidad constante, material/ID originales, reverse-Z y comparación con oráculo de esas **celdas** | Equivalencia con la geometría original de Blender; cero discrepancias numéricas; coste aceptable en móviles |

### Puntos concretos del código

- `gpu_compute/shaders/lie27_regions.glsl`: el encabezado establece que los buffers de vértices/triángulos **vinculan y deforman** muestras, pero no se rasterizan. `skin_sample`, `lid_support`, `covered`, `pixel_depth` y las fases 2/3/8 hacen proyección, profundidad, selección y acumulación de huellas. `lid_support` limita solo ciertos parches triangulares; **no** es un ray-intersector general.
- `gpu_compute/lie27_regions_effect.gd`: valida registros de 80 bytes por muestra y recursos del maestro; expone readback de `projected`, `depth` y `winners`, adecuados para auditar la primera superficie sin depender del color.
- `gpu_compute/shaders/lie16_pipeline.glsl`: cada muestra aporta huella de cobertura y profundidad de plano tangente; la selección por píxel y los filtros conservan compatibilidad de propietario/normal, pero no reconstruyen necesariamente una superficie cerrada.
- `gpu_compute/shaders/lie_direct_views.glsl` (rama experimental): hasta tres capturas angulares; correcciones y dos refinamientos, sin recorrido exhaustivo del campo de celdas y sin fallback. Un `capture_hit` fallido no prueba inexistencia de superficie.
- `tools/lie_native_surface.py` (rama experimental): solo fusiona celdas contiguas con **bits de profundidad idénticos**; crea cuadriláteros con dos triángulos, no reconstruye la topología de la malla fuente.

Referencias:
- [LIE-14](../docs/LIE_14_RIGID_PERCEPTION_MASTERS.md), [LIE-16](../docs/LIE_16_STABLE_QUALITY.md), [LIE-22](../docs/LIE_22_MODULAR_MASTERS.md), [LIE-26](../docs/LIE_26_ANATOMICAL_MOTION.md), [LIE-27](../docs/LIE_27_REGIONS_AND_FACE.md), [checkpoint LIE-27](../docs/checkpoints/LIE27_CONTINUATION.md).
- [Código LIE-27](../gpu_compute/shaders/lie27_regions.glsl), [efecto LIE-27](../gpu_compute/lie27_regions_effect.gd), [shader LIE-16](../gpu_compute/shaders/lie16_pipeline.glsl).
- [Rama LIE native-depth](https://github.com/heliossamuelhernandezreyes/Lie-Engine/tree/work/lie-native-depth), [diagnóstico 2.5](https://github.com/heliossamuelhernandezreyes/Lie-Engine/blob/work/lie-native-depth/docs/LIE25_PHONE_POSE_DIAGNOSIS.md) y [recuperación native](https://github.com/heliossamuelhernandezreyes/Lie-Engine/blob/work/lie-native-depth/docs/LIE_NATIVE_DEPTH_RECOVERY.md).

## Prueba conceptual de información insuficiente (no confundir con una prueba GPU)

Un conjunto **finito** de posiciones, normales y radios de muestras no determina de manera única una superficie continua arbitraria sin hipótesis adicionales. Por ejemplo, en una región sin centros de muestra pueden existir dos superficies suaves que coinciden exactamente en los puntos observados (y sus derivadas en dichos puntos) y difieren en el interior mediante una protuberancia suave compacta. Sus atributos muestreados son indistinguibles pero un rayo de cámara intermedio puede intersectar a distintas profundidades.

**Límite de este argumento:** no demuestra que un activo *particular* de LIE tenga esa protuberancia ni que todas las representaciones con parches/celdas sean insuficientes. Demuestra por qué hace falta un contrato adicional de continuidad/topología/cobertura **o** delimitar explícitamente la clase de superficies admisibles. En una representación definida deliberadamente como celdas planas, el campo finito **sí** puede definir el objeto que se renderiza, aunque no equivalga a la malla original.

## Evidencia negativa y positiva ya registrada (no reejecutada en esta auditoría)

1. **Pared, cámara de fallo LIE 2.5:** yaw `-72.90939846038818`, elevación `2.0563994513617607`, distancia `0.6`, 720². Frente al backend `regions`, `views` pierde **6,531** impactos válidos; `views_fast` pierde **31,493**. `regions` es referencia comparativa, **no** verdad geométrica de fuente. Queda demostrado que un número acotado de capturas angulares y pasos de refinamiento no garantizan coincidencia.
2. **Native-cell para la misma pared:** las discrepancias de cobertura frente a `regions` bajan a **1** píxel en la pose exacta. Contra el oráculo independiente de **celdas finitas** (muestra dirigida, 2,460 rayos, 1,259 impactos del oráculo), no hubo faltantes/sobrantes en los rayos seleccionados, pero sí **7 errores de propietario** y **7 profundidades** por encima de 20 micrómetros; máximo **4.413 mm**. **No extrapolar** esa muestra a una tasa poblacional.
3. **Artefactos de apariencia:** el grano oscuro persiste en native con y sin sombras; corregir cobertura y profundidad no garantiza corregir apariencia. El checkpoint LIE-27 también localiza gran parte de las manchas orbitales en el sombreado cuando la matriz de ganadores no cambia.
4. **Regiones anatómicas protegidas:** el checkpoint LIE-27 conserva cero faltantes en cinco casos específicos de mentón y cero tejido interior indebido en trece casos orbitales protegidos. Una verificación local del cuello detecta dos faltantes en 5,262 píxeles con fuente. **Estos resultados son locales** y no certifican toda la anatomía, poses o cámara.

## Auditoría ejecutable propuesta: separar dato, visibilidad y sombreado

### A. Definir un contrato único por superficie

Por activo y por pieza se necesita:

- `surface_id`, `part_id`, `material_id`, versión y procedencia de la fuente;
- transformación actual y (para animación) anterior; límites conservadores;
- capacidad declarada de consulta `first_hit(ray, pose)` y `surface_attributes(hit)`, o estatus explícito `approximate-only`;
- especificación de soporte: parches finitos, límites, conectividad/orientación y comportamiento en discontinuidades;
- cobertura que puede certificarse: cámaras/ángulos/poses/densidad de muestra; tratamiento de superficies internas y disoclusión;
- distinción entre profundidad geométrica, normal geométrica y normal de sombreado.

**Esto es un contrato para experimentar, no la exigencia de introducir mallas densas o cambiar Godot.** Se puede cumplir con celdas, parches, superficies implícitas o un adaptador híbrido.

### B. Comparar tres niveles con el MISMO estado de escena

1. **Oráculo de fuente**: rayos contra el original Blender/analítico transformado exactamente por la pose de referencia; está disponible solo en la prueba, nunca como atajo para el render LIE.
2. **Oráculo de representación**: rayos contra lo que el activo LIE afirma representar (por ejemplo, láminas de celda). Pregunta: ¿se perdió información durante la captura/compilación?
3. **Resultado GPU**: buffers de profundidad, ganador/propietario, atributos y fotograma. Pregunta: ¿se consulta/renderiza correctamente una representación suficiente?

Atribución:
- fuente ≠ representación → defecto de **información/modelado/compilación**;
- representación ≠ GPU → defecto de **consulta/precisión/cobertura**;
- ambas coinciden, RGB difiere → defecto **apariencia/iluminación/filtrado**;
- discrepancias solo en movimiento → **continuidad temporal, pose o invalidación de historial**.

### C. Matriz mínima de casos

| Activo | Casos prioritarios | Oráculo independiente y scripts que ya existen |
| --- | --- | --- |
| Cilindro rígido LIE-14 | Órbita completa, aproximaciones, silueta, espesor y descarte al salir de cámara | Cilindro analítico de `tools/lie14_reference.py`; `gpu_compute/test_lie14_rigid.gd` |
| Pared modular LIE-22 / rama LIE 2.5 | Frontal, rasante, interior/exterior de hueco, esquina, ladrillo eliminado; pose de fallo y ±0.1°; luces on/off | Blender de pared y `tools/lie22_verify_captures.py`; para 2.5, `tools/lie_direct_views_diagnosis.py` y `tools/lie_native_oracle.py` |
| Rostro y cuerpo LIE-27 | Mentón, cuello, ojo abierto/cerrado, perfil ±35°, parpadeo intermedio, movimiento de cabeza, dedos y pose entre capturas | Oráculos de `tools/lie27_coverage_reference.py` y `tools/lie27_reference.py`; `gpu_compute/test_lie27_gpu.gd` |

**Observación:** las herramientas de LIE 2.5 y su banco atribuido viven en una rama experimental; no mezclar sus números con el taller anatómico en `main` como si fueran una sola escena.

### D. Métricas y puertas de aceptación

Guardar para cada cámara/pose: ancho/alto, matrices, near/far, fuente/paquete/hash, sombra habilitada, resolución, render backend y SHA de programa.

- **Cobertura:** falso negativo (fuente impacta, LIE no), falso positivo (LIE dibuja sin fuente) y IoU global / por segmento; separar píxeles de bordes con una máscara explícita.
- **Propietario:** `surface_id/part_id/material_id` de primer impacto; contar errores incluso si la silueta coincide.
- **Profundidad:** error absoluto en metros, p50/p95/p99/máximo, con umbral declarado según escena y escala; no aceptar solo una silueta correcta.
- **Normales y materiales:** ángulo de normal geométrica; identificador/atributos; normal de sombreado por separado.
- **Movimiento:** discrepancias por paso de cámara y animación; comparar historial activado/desactivado y referencias de pose; medir flicker y aparición de huecos.
- **RGB e iluminación:** comparar **solo después** de proteger cobertura/propiedad/profundidad; separar sombras, material y postprocesamiento.

**No fijar una tolerancia universal inventada** para personajes microscópicos, escala humana y pared. Fijar umbrales previos por escena y documentar el intervalo de incertidumbre del oráculo. Guardar errores, no solo “PASS”.

### E. Comandos de reproducción existentes (requieren activos externos y Godot/Blender preparados)

```bash
# Cilindro / rig de referencia, después de generar su maestro documentado:
python3 tools/lie14_reference.py gpu_compute/captures/rigid_master
godot --path gpu_compute --script res://test_lie14_rigid.gd

# Pared modular, con los masters LIE-22 generados:
python3 tools/lie22_verify_captures.py gpu_compute

# Cuerpo y rostro, tras preparar el banco anatomy27:
python3 tools/lie27_reference.py gpu_compute/captures/anatomy27 --fixture gpu_compute/fixtures/lie27-rig.json
godot --headless --path gpu_compute --script res://test_lie27_regions.gd
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --script res://test_lie27_gpu.gd

# LIE 2.5: usar solo desde work/lie-native-depth con banco y capturas restaurados:
# consultar docs/LIE25_PHONE_POSE_DIAGNOSIS.md y docs/LIE_NATIVE_DEPTH_RECOVERY.md
```

Estos comandos existentes **no se ejecutaron** en esta auditoría: el banco de muestras y los activos Blender externos no están disponibles en el entorno del conector. Sus resultados citados son los resultados preservados por el proyecto.

## Decisión arquitectónica recomendada

**Conservar** (1) jerarquía/colisiones invisibles, (2) captura de atributos finos, (3) maestros compartidos y (4) deformación por rig.

**Añadir como investigación**, no como reemplazo impuesto: un contrato de **superficie canónica consultable** que pueda responder al rayo actual de cámara y de luz y devolver un primer impacto con profundidad, propietario y material, sin depender del ángulo de captura cuando el activo anuncie cobertura exacta.

No decidir todavía “usar triángulos”, “usar más capturas”, “usar SDF”, “usar temporal” ni “migrar de motor”. Primero seleccionar **un mismo caso de fallo** y demostrar cuál de los tres niveles pierde la superficie. Después comparar representaciones candidatas en exactitud **antes** de comparar tiempos.

### Siguiente experimento mínimo que realmente discrimina

Reutilizar la pared de la pose LIE 2.5 con las mismas matrices y el mismo campo atribuido:
1. Oráculo `source` del objeto original (si está disponible) y oráculo `cell-sheet` de representación separadamente;
2. exacta máscara/ID/profundidad de `regions`, `views` y `native`, sombras deshabilitadas;
3. barrido corto ±0.1° y desplazamiento de cámara con capturas por fotograma;
4. clasificar cada píxel erróneo en **ausente en activo**, **consulta incorrecta**, **propietario/depth errado** o **solo sombreado**.

**Criterio de éxito de esta etapa:** emitir un informe firmado por hashes donde todos los errores observados estén clasificados por nivel; no FPS, ni filtros que oculten fallos, ni afirmación de que un renderizador nuevo ya está listo.
