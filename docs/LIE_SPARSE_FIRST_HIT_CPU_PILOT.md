# LIE 2.5 — primer prototipo de resolución dispersa del primer impacto

**Fecha:** 2026-11-05. **Rama:** `research/lie-geometric-sufficiency-audit` (PR #73, borrador). **No modificar `main`.**

## Qué se ha implementado de verdad

- **Detector independiente del renderizador `regions`:** `tools/lie_native_sparse_first_hit.py` lee **solo** el buffer nativo `world.xyz + owner`, el paquete real de cámara, las transformaciones de las 97 instancias y el **layout de captura** autenticado. Identifica: (a) impactos del propietario ganador cerca de un borde de texel finito y (b) píxeles vacíos con tres vecinos cardinales válidos.
- La rutina del borde transforma `world.xyz` al sistema local del ladrillo de origen, determina la cara por la entrada del rayo a la caja, proyecta a coordenadas `(u,v)` en texeles, y mide la distancia a `floor(u)`/el entero siguiente. Usa `owner - 1 // 9` para el banco de 96 ladrillos; los propietarios fuera de rango, incluido mortero, **no** reciben detección de bordes inventada.
- **Trabajo disperso real (CPU):** la rutina opcional `--resolve-with-oracle` traza únicamente los rayos marcados contra las celdas originales, con el oráculo float64 de `work/lie-native-depth`. Produce propuesta de primer hit `(pixel, owner, distancia, world.xyz)` y marca expresamente que **no es** un shader reparado ni incluye normales, material, profundidad reverse-Z ni certificación independiente.
- **Controles y evidencia:** pruebas adversarias CPU `tests/test_lie_native_sparse_first_hit.py` y Actions aislada con el APK registrado, datos reales Vulkan, hashes del archivo de cámara/buffer y comparación contra errores archivados del oráculo. La selección de píxeles **no consulta** el oráculo ni ejecuta el segundo backend.

## Medición con los mismos fotogramas auténticos

GPU original: Godot 4.7.2, Vulkan por software llvmpipe, tres cámaras 720×720, pared con banco autenticado SHA-256 `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.

**Corrida de flags:** [GitHub Actions 42059480914](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42059480914), artefacto **13431850465**, `lie-sparse-native-only-risk-evidence`.

| Margen del ganador (celdas) | Pose 0 flags | Pose 1 flags | Pose 2 flags | Errores del corpus detectados |
|---|---:|---:|---:|---:|
| 0.002 | 2,131 | 2,033 | 2,045 | **11 / 25** (2/7, 3/7, 6/11) |
| 0.01 | 6,086 | 6,053 | 6,088 | **12 / 25** (2/7, 4/7, 6/11) |
| 0.05 | 25,886 | 25,850 | 25,880 | **17 / 25** (4/7, 4/7, 9/11) |

Denominador por cámara: **518,400 píxeles**. La primera fila representa aproximadamente **0.40%** de la pantalla; la tercera, cerca de **5%**. El corpus original de 25 errores es una muestra **deliberadamente dirigida**, no un muestreo aleatorio ni todos los errores de cada fotograma. No inferir probabilidades de éxito global a partir de 11/25 o 17/25.

El principal descubrimiento negativo: **la proximidad al borde de la superficie FINAL no detecta los candidatos que Vulkan descartó antes del depth test**, ni todos los errores de profundidad con propietario correcto. La detección en un único buffer final tiene un límite estructural.

## Prueba de resolución CPU sobre los 2,033 flags de la pose 1

**Corrida de recuperación y raycasting real:** [GitHub Actions 42059912858](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42059912858), artefacto **13431686039**, `lie-sparse-native-only-risk-evidence`. Restaura las **celdas de captura** originales del APK comprobado y usa el oráculo float64 archivado.

Entre los 2,033 rayos revisados, la misma representación finita detectó **16** discrepancias con los resultados Vulkan:

| Clasificación vs oráculo de celdas | Casos |
|---|---:|
| Misma identidad de propietario, profundidad diferente >20 µm | **8** |
| Propietario distinto | **6** |
| Vulkan vacío, oráculo impacta | **1** |
| Vulkan impacta, oráculo vacío | **1** |
| **Total** | **16** |

Dos ejemplos reproducidos:

- **Píxel (416,434), pose yaw -0.1°:** Vulkan propietario 80, distancia 2.690960059 m; oráculo propietario 83, distancia 2.882374825 m. Un fragmento espurio del ladrillo anterior gana por la ambigüedad de su frontera.
- **Píxel (108,422):** Vulkan no dibuja superficie; oráculo encuentra propietario 326 a 1.201511559 m.

La prueba de 2,033 rayos revela más errores que el corpus fijo anterior, pero sigue sin ser un censo. La rutina correctiva reutiliza el **mismo oráculo** que define la referencia; por tanto, **sus resultados son un límite superior de corrección posible**, no una validación cruzada por algoritmo independiente. No enviar a producción como corrección completada.

## Diseño concreto de la siguiente etapa Vulkan

### 1. Señal de candidato ANTES del descarte

En el fragment shader nativo, **antes** de `discard` por soporte half-open, identificar incertidumbre numérica de cada **candidato**, no solo del ganador visible. Escribir `atomicOr` en un bitset R32UI de `ceil(720²/32)` palabras (16,200 palabras = 64,800 bytes), con alcance de pantalla y fase de reset por cámara. Marcar también riesgos por conflicto de profundidad, discontinuidad y candidatos cuya caja pueda ganar aunque un fragmento se descarte.

**Ese tamaño es únicamente el del bitset**, no incluye estructuras de candidatos, atlas, listas de tiles, ni recursos de sombreado. Asegurar soporte de atomics, coherencia entre etapas y coste medido en Mali. El detector de riesgo es conservador; flags falsos son aceptables, impactos perdidos no.

### 2. Compactar y resolver por rayos

Un compute pass de prefijo/compacción convierte bits en una lista de IDs de píxel; un kernel de rayos busca en el **campo capturado real**, usando rectángulos/intervalos conservadores existentes en LIE. A diferencia de ordenar solo los fragmentos que sobrevivieron al shader, el recorrido debe poder encontrar superficies **que no se rasterizaron o quedaron descartadas**. Debe resolver el primer impacto, incluido mortero, capa, profundidad y propietario, mediante reglas half-open uniformes y una política explícita de empates.

Los 48,958,966 triángulos auxiliares del ensayo nativo siguen siendo un coste estructural; un nuevo solve disperso no garantiza que el paso principal sea eficiente en móvil.

### 3. Publicación coherente

El mismo hit seleccionado alimenta `world.xyz`, `owner`, `normal`, `material` y profundidad reverse-Z. Reemplazar solo el dueño o el color de un píxel fabricaría artefactos. También hay que mantener sombras y materiales con la misma geometría de impacto, pero evaluarlos por separado.

### 4. Puertas de aceptación (no alcanzadas)

1. Detector independiente de `regions`; rayos del oráculo del campo capturado que fallen **nunca** quedan sin marcar en todos los ensayos dirigidos.
2. Resolver por una implementación independiente del oráculo histórico, con propiedad y profundidad correctas en las tres cámaras, y desplazamientos de cámara subpíxel.
3. **Cero errores nuevos y cero huecos nuevos** en todos los píxeles modificados (no solo los incluidos en la muestra).
4. Prueba con luz/sombras desacopladas y conservación de datos ópticos.
5. Medición en una GPU Mali real, incluyendo despacho, sincronización, memoria, tiempo hasta imagen, temperaturas y FPS; apuntar a móviles modestos, no solo de gama alta.
6. Mantener pendiente **fuente Blender original → captura LIE**, que no puede verificarse con el APK y las celdas capturadas.

## Estado de integración

✅ Detector nativo independiente de `regions`, trabajo disperso, corpus de regresión, replay de captura en CPU, CI y procedencia reproducibles.  
❌ No existe aún captura de **todos** los fragmentos ambiguos antes de su descarte, ni kernel GPU de compactación, ni corrector integrado a Godot, ni prueba de fidelidad con la malla original.

**Decisión:** conservar esta infraestructura en PR #73 como herramienta experimental. No fusionar a `main` ni declarar resuelto el primer impacto.
