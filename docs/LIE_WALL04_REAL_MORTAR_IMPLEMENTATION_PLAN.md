# LIE-WALL-04 — Integración de mortero fotográfico con relieve físico

Estado: **especificación técnica; implementación y certificación pendientes**.
Antecesor: PR #43, rama `experiment/lie-wall03-coverage-mortar`.
No modificar los bancos históricos LIE-WALL-01/02/03 ni el escaneo de Stratford New Place Brick Ver 2.

## Objetivo y reglas irrenunciables

- Sustituir la apariencia de junta como plano procedural uniforme por mortero con **muestras 3D procedentes de datos fotográficos PBR** (posición/depth, normal, albedo, roughness y apoyo geométrico).
- Preservar los 96 ladrillos originales, sus muestras XYZ y COLOR_0 byte a byte, la licencia CC BY 4.0, 3 LOD y el SHA del banco de ladrillos.
- Una sola `SpatialEnvelope` (`BoxShape3D`) gruesa, **sin caras visibles**; sin mallas de fuente renderizadas. Los 96 AABB actuales sirven sólo para luz, no son colisionadores adicionales.
- Conservar transporte de luz LIE-11 con irradiancia RGB, absorción y rebotes; no introducir una segunda luz ficticia ni AO multiplicado dos veces. Permitir coste de cómputo/LOD independiente para mortero.
- LIE-WALL-03 debe seguir restaurable, visible y ejecutable aunque LIE-WALL-04 falle. Nada de reemplazar en caliente los artefactos SHA-locked.

## Fuentes autorizadas y su estado

Principal a evaluar: Poly Haven **Brick Wall 13**, https://polyhaven.com/a/brick_wall_13 .
- CC0 declarado por proveedor, 8K, anchura de captura declarada 2 m (~41 px/cm); mapas de diffuse, normal GL, roughness, displacement, AO. Juntas profundas y gastadas. Fuente: https://polyhaven.com/license .
- Fuente alternativa: Poly Haven **Brick Wall 001**, https://polyhaven.com/a/brick_wall_001 , 8K, anchura 3 m (~27.3 px/cm), juntas de otra tipología. No mezclar normal/altura/color de distintas fuentes sin registro geométrico.
- Descargar desde endpoint oficial verificable. Conservar URL, archivo, variante, resolución real, SHA-256 de cada mapa y licencia en `source-lock.json`. Rechazar mapas faltantes o incoherentes. La mera profundidad de bits del displacement NO prueba milímetros absolutos; documentar calibración física / incertidumbre.
- PolyScan Brick Wall AD4CA4 queda como candidato en espera: página CC0, pero enlace 8K no confirmado y términos web restrictivos de redistribución. No incluirlo en distribución sin esclarecer disponibilidad y derechos.

## Arquitectura y orden de trabajo

### Fase 0 — prueba de factibilidad y selección (sin cambios en el renderer)
1. Consultar API oficial Poly Haven, verificar formatos/resoluciones y URLs.
2. Descargar juego de mapas coherente de una misma fuente, preferiblemente displacement EXR, diffuse, normal OpenGL, roughness y AO; autenticar hashes.
3. Revisar visualmente si sus juntas realmente contienen la irregularidad deseada, sin asumirlo sólo por la resolución 8K.
4. Estimar escala a partir de los 2 m declarados y analizar si el displacement contiene escala métrica verificable; si no, declarar campo de altura *relativo* y ajustar offset/amplitud por referencia de junta real con incertidumbre explícita.

### Fase 1 — LIE-MORTAR-01: extracción auditada de franjas y cruces
1. Detectar en el albedo y displacement las zonas de mortero, horizontales, verticales y encuentros T. Crear máscara validada visualmente, ligada a coordenadas de TODOS los mapas de origen.
2. Excluir cerámica/rocas del ladrillo donante; conservar margen y una `confidence mask` para degradar o rechazar zonas ambiguas. Eliminar texturas con bordes incoherentes o sombras fotografiadas residuales.
3. Construir un atlas offline de franjas de mortero y cruces con coordenadas físicas; todos los canales deben compartir la misma transformación, orientación y procedencia.
4. Guardar ejemplos positivos/negativos de segmentación, escala y huecos. No inventar granos con ruido como sustituto de datos reales.

### Fase 2 — reconstrucción de superficie de junta 3D
1. Mantener el aparejo y posicionamiento nominal de LIE-WALL-03 (8x12, ancho de junta 8.5 mm como nominal, no constante visual).
2. Para cada junta, muestrear una tira del atlas con semilla determinista por junta y decorrelación de repeticiones. Preservar orientación métrica, perfil de borde y sincronía entre mapas.
3. Transformar desplazamiento de fuente en `z(x,y)` alrededor del plano nominal, no usar una textura plana; calcular/validar normales a partir de gradientes calibrados y contraste con mapa Normal GL. Añadir muestras del cuerpo del mortero, acumulaciones y ligera variación del labio SOLO donde fuente y máscara tienen evidencia.
4. Resolver profundidad contra la superficie escaneada original: depth test por muestra y prohibición de sobrepintar caras intactas. Una alteración de borde sólo se acepta si tiene correspondencia plausible, con límite espacial pequeño y comprobación de intrusión.
5. Generar muestras de mortero compatibles con ABI actual de 80 bytes (posición, radio de soporte, normal, código de parche LIE-11, albedo lineal, roughness y soporte). No convertir las seis caras de la caja espacial en superficie visible.
6. Empaquetar `mortar-bank.zlib`, `mortar-catalog.json`, `source-lock.json`, certificados SHA y LOD de mortero (alto/medio/bajo). No asumir límite numérico de muestras sin medir.

### Fase 3 — adaptación renderer y transporte
1. Nuevo `tools/lie_wall04_bake.py`, `tools/lie_wall04_restore.py`, `gpu_compute/lie_wall04_mortar_effect.gd`, laboratorio `lie_wall04_mortar_lab.tscn` y shader separado de 03.
2. En `gpu_compute/shaders/lie_wall03_coverage.glsl`, stage 8 actualmente llama a `real_joint_light()`, que intersecta plano z fijo y usa albedo constante vec3(.295,.273,.247), antes del rellenado de huecos. En 04 no usar esa ruta como apariencia principal: el mortero debe participar en profundidad/proyección y recibir LIE-11 desde sus nodos antes del blend final.
3. Mantener el filtrado de pequeños huecos **solo del mismo ladrillo**; separar grupos de muestras de mortero para que no se copien colores entre ladrillo y junta, ni entre juntas distintas.
4. Inicialmente reutilizar 8 nodos de mortero, IDs 864..871, más 864 nodos del ladrillo (872 total). Si la variación espacial o de iluminación lo exige, versionar esquema y probar subdivisión controlada sin superar capacidad actual; nunca falsificar sombras por parche.
5. Sombras y normals deben variar físicamente con la micro-superficie del mortero. Comprobar conservación de energía de LIE-11. Si LIE11 con nodos por hilada es insuficiente, registrar resultado negativo y proponer un transporte más localizado antes de declarar hero quality.
6. Permitir `mortar_mode = legacy | captured` y `mortar_quality = low | medium | high`. Misma cámara/iluminación para A/B; el modo legacy sigue válido.
7. Evitar introducir varias capas 8K sin razón en GPU de ejecución: la fuente se usa offline para producir muestras LIE compactas.

### Fase 4 — pruebas de conservación y calidad
- Unitarias: hashes de fuente/bancos, CC0 del mortero, licencia CC BY del ladrillo y 96 piezas constantes; 1 colisionador, 0 triángulos fuente dibujados, mismo brick XYZ/RGB; ABI, 3 LOD y orden de nodos.
- Matemáticas: coordenadas UV/escala física y normal, transferencia de color lineal; análisis de profundidad con borde y de oclusión; tests de ausencia de contornos rectangulares en juntas y de fugas a ladrillos.
- Imágenes **Godot Vulkan nativas**, no ilustraciones sintéticas: 1080², vista frontal, cercana, rasante, ángulos oblicuos, 2 luces, distintas absorciones y A/B legacy/captured.
- Métrica perceptual: continuidad del perfil, variabilidad de anchura/profundidad, repetición visible, manchas y bleeding contra ladrillo, black-pixel ratio y artefactos silueta. Un material coherente no equivale automáticamente a fotorrealismo.
- Bench: `gpu_ms`, frame time CPU, VRAM, PSS/RSS, estabilidad y coste incremental a tres LOD. Mesa llvmpipe es sólo verificación funcional; para FPS y memoria móvil exigir Android físico. El punto de partida de WALL-03 en Mesa era aproximadamente 495 MiB internos a 2160².
- No publicar benchmark si timeout o muestras insuficientes. Registrar pruebas fallidas e incertidumbre.

## Entregables previstos

- `assets/material_masters/mortar/hero/real_masonry_joint/material_manifest.json` y fuente SHA-locked.
- `tools/lie_mortar01_acquire.py`, `tools/lie_mortar01_extract.py`, `tools/lie_wall04_bake.py`, `tools/lie_wall04_restore.py`.
- `gpu_compute/assets/lie_mortar01/`, `gpu_compute/assets/lie_wall04/`, `gpu_compute/lie_wall04_mortar_lab.tscn`, shader/effect v04.
- `tests/test_lie_mortar01.py`, `tests/test_lie_wall04.py`, workflow GPU con capturas, hashes y benchmarks independientes, informe A/B y limitaciones.
- Pull request **draft** separado, sin merge hasta que las muestras del mortero estén verificadas y los regresivos pasen.

## Puertas de avance

G0: fuente obtenible, mapas válidos, derechos claros, SHA registrado.
G1: máscara/atlas de junta aprobado visualmente y métricamente; sin contaminación del ladrillo donante.
G2: banco LIE restaurable y geometría de mortero no plana, con normales/relieve verificables.
G3: renderer Vulkan A/B, ladrillos byte-identical, una caja invisible, sin mezcla ni halo.
G4: quality review contra fotografías pertinentes, rendimiento nativo objetivo y evidencia reproducible.
Si G0/G1 fallan, detener integración de 04 y volver a selección de fuente, NO introducir ruido para fingir escaneo.

## Riesgos

El material de referencia es una pared fotografiada, no un asset aislado de mortero. La extracción es difícil y requiere validación manual; las juntas del modelo donante no coinciden 1:1 con las de Stratford. Sus mapas pueden representar desplazamiento relativo y no medición absoluta. Una buena resolución no implica buena fidelidad de altura. Mantener estas incertidumbres explícitas.

## Resultado real de implementación parcial (13 de octubre de 2026)

Evidencia, fuentes y archivos reproducibles, todos en esta rama experimental:

- Banco 8K CC0 `brick_wall_13`: hashes de diffuse, normal GL, displacement, roughness, AO en `assets/material_masters/mortar/hero/real_masonry_joint/source/source-lock.json`.
- 6 recortes horizontales y 6 verticales de la fuente 8K. Máscaras y PBR alineados en `derived/`. **Advertencia:** candidato **G1 NO APROBADO**; la extracción detecta algunas grietas del ladrillo donante como mortero. El desplazamiento se usó como relativo; su escala milimétrica no está calibrada.
- `gpu_compute/assets/lie_mortar01/`: **154.610 muestras de mortero 3D**, 80 B/muestra, distribuidas en tres LOD de 113.433 / 28.549 / 12.628. La fuente es fotografiada, pero las uniones y reubicación sobre el muro son reconstrucciones.
- `gpu_compute/assets/lie_wall04/`: banco conjunto de **686.450 muestras** en tres LOD (497.433 / 153.349 / 35.668). Los 96 ladrillos originales, sus XYZ y RGB se conservan **byte por byte**; el mortero procedural anterior se reemplaza sin modificar el banco WALL03 original.
- Godot 4.7.2 software Vulkan (Mesa) compiló e hizo capturas auténticas `evidence/LIE-WALL04-CapturedMortar-Neutral.png` y `evidence/LIE-WALL04-CapturedMortar-Raking.png`. Un modo DIAGNÓSTICO **no físico** marca en verde sólo las muestras fotográficas realmente ganadoras de los tests de profundidad: `evidence/LIE-WALL04-CapturedMortar-CoverageDEBUG.png`.
- Imagen a 1080×1080, cámara/luz constantes: primeras 89.918 muestras mortero en los 3 LOD produjeron **36.635** píxeles diagnosticados como mortero y **61.408** píxeles opacos casi negros; la variante densa produjo **45.737** píxeles de mortero y **58.995** opacos casi negros. Cambio: **+9.102 muestras visibles (+24,8%)** y **-2.413 opacos negros (-3,9%)**. El área visible total pasó de 318.339 a 321.876 píxeles.
- La energía del mortero fotografiado SI aparece en el shader: los 45.737 píxeles diagnosticados tenían luminancia no negra. Persisten bandas oscuras y zonas sin cobertura **fuera** de las muestras de mortero. No falsificar el origen del negro ni eliminar la geometría real del ladrillo para pintarlo.
- **El resultado NO está aceptado como fotorrealista**. No hay validación G1 de máscaras, referencia fotográfica ajustada a la misma cámara y exposición, prueba de intersección real de las aristas escaneadas ni benchmark GPU de Android. La medición Mesa Vulkan es una prueba funcional, no una afirmación de FPS del teléfono.

Siguiente bloqueo técnico: diferenciar con una máscara de propietario/luz los píxeles de ladrillo oscuro, la ausencia de muestras del escaneo y los huecos nominales de junta; después reconstruir el perfil de contacto ladrillo-mortero con fuentes fotografiadas sin invadir la cara escaneada. Comparar A/B de cobertura y aspecto bajo igual luz, vigilar sobrepintado y evitar presupuestos de GPU desconocidos. Mantener separado el modo de diagnóstico verde del material final.
