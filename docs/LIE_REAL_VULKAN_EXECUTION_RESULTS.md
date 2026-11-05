# LIE 2.5: nueva verificación Vulkan real contra el banco atribuido

**Fecha:** 2026-11-05. **Rama:** `research/lie-geometric-sufficiency-audit`, PR #73.  
**Ejecución registrada:** [GitHub Actions 42026307732](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42026307732).  
**Artefacto inicial:** `lie-real-vulkan-native-triplet-evidence` ID 13414805679.  
**Software:** Godot 4.7.2, Vulkan 1.4.335, llvmpipe LLVM 21.1.8 por software. **No es rendimiento del Mali-G720 ni una prueba de FPS Android.**

## Procedencia recuperada y ejecución

El workflow descargó desde GitHub Actions el APK verificado `LIE-Vistas-2.5.0.apk`, artefacto histórico 12242222027 del run 39371606348.

- SHA-256 APK: `e6af19560fb7183eab71c85411867ebe2e7cc84fd131ce83e7c87212`.
- SHA-256 banco de 521,257 muestras: `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`.
- Se recuperaron **39 archivos capturados**; el script validó hashes de `library.bin`, `direct/depth.bin`, `direct/normal.bin` y `direct/color.bin`.
- Se reconstruyeron shaders, rectángulos de celda y proyecto de prueba desde `work/lie-native-depth` sin tocar `main`.
- El log confirmó 25 comprobaciones funcionales Vulkan completadas; seis fotogramas `regions`/`native` (tres cámaras) sin fallback.

## Qué comparamos exactamente

**Oráculo:** `lie_native_oracle.py` de la rama experimental, rayos float64 contra celdas finitas con las capturas originales recuperadas.  
**GPU:** readback `native_surface.surface_world` real del motor Godot, con paquetes originales `views` y `proxies`.  
**Referencia secundaria:** backend `regions`, que no es verdad geométrica de la fuente.

Los rayos fueron **seleccionados intencionadamente**: todas las discrepancias de cobertura y propietario regions/native, más muestras fijas de aciertos y fondo. Los porcentajes sobre estos subconjuntos no estiman tasas de error sobre 720×720 píxeles.

Las cámaras tienen yaw base **−72.90939846038818°**, elevación **2.0563994513617607°**, distancia **0.6**, y desplazamientos yaw ±0.1°. Luz desactivada para comparación geométrica; sombras probadas aparte para el ensayo funcional.

## Resultados medidos — representación vs Vulkan

| Cámara | Rayos evaluados | Impactos comunes | Faltantes | Sobrantes | Dueño distinto | Error de distancia >20µm | Máximo error de distancia |
|---|---:|---:|---:|---:|---:|---:|---:|
| Original | 2,460 | 1,259 | 0 | 0 | 7 | 7 | 4.413 mm |
| yaw −0.1° | 2,483 | 1,275 | 1 | 0 | 6 | 6 | **191.415 mm** |
| yaw +0.1° | 2,478 | 1,275 | 1 | 0 | 8 | 10 | 4.254 mm |

**El error de 191.415 mm** se presenta en la segunda pose, píxel x=416, y=434; el oráculo predice propietario 83 y la GPU reporta 80. Es una discrepancia de primer impacto que necesita discriminar borde/empate/oclusor; el simple hecho de existir un error grande no demuestra todavía si es defecto de representación, selección Vulkan o ambigüedad de borde en el oráculo. Los demás errores de propietario tampoco se declaran correctos.

Para referencia, el backend `regions` frente al nuevo `native` mostró respectivamente 1, 8 y 3 faltantes en estas cámaras y 59, 75 y 74 desacuerdos de propietario en los conjuntos seleccionados. La recuperación native es sustancial para cobertura, pero **no significa identidad exacta**.

## Interpretación arquitectónica

1. **Sí:** la representación de celdas finitas conserva suficiente información para que el oráculo independiente obtenga hits incluso donde `native` se equivoca. En esas coordenadas, el fallo aparece en la consulta/rasterización/profundidad sobre la representación, no necesariamente en la captura.
2. **No:** lo anterior no demuestra que la **fuente Blender → celdas** sea fiel. El comparador informa `source_status: NOT PROVIDED` precisamente porque la malla original aún no se incorporó.
3. **No:** el éxito de los 25 checks de ejecución no es una puerta estricta de visibilidad; las discrepancias geométricas registradas incumplirían una aceptación de equivalencia perfecta.
4. **Apariencia sigue separada:** grano, sombreado y propiedades ópticas necesitan otra ablación; este informe no mide RGB.

La arquitectura actual de 48,958,966 triángulos auxiliares para la pared sigue siendo una estrategia de corrección de referencia, no una propuesta móvil eficiente. No sustituir la arquitectura ni optimizar FPS con esta evidencia aislada.

## Siguiente diagnóstico experimental

Comparar distancias al borde de celda y separación al segundo impacto por píxel incorrecto, priorizando (416,434) en la pose −0.1° y los dos falsos negativos de las poses vecinas. Conservar los archivos binarios de lectura real; revisar quién gana al cambiar ±1 subpíxel y al usar precisión/half-open bounds consistentes. Exigir también un raycast Blender autenticado del original si se desea certificar pérdida de datos por captura.

La malla original documentada en `catalog.json` se atribuye a *Stratford New Place Brick Ver 2*, Centre-of-Archaeology (Sketchfab), CC BY 4.0, con 500,000 triángulos; el catálogo no contiene por sí solo el mesh original ni resuelve su transformación exacta en la pared.

## Segunda ejecución — registros completos y distancias de borde

[GitHub Actions 42027026472](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42027026472): **éxito**, usando de nuevo banco original restaurado, Godot 4.7.2 y Vulkan por software. Artefacto de evidencia: `lie-real-vulkan-native-triplet-evidence`, ID **13414771717**. Contiene readbacks binarios completos `world`, `views` y `proxies` de poses 0, 1 y 2, JSON de diagnóstico y logs, más dos PNG de apariencia con sombras. Los binarios se conservaron sin cambiar la representación.

La comparación incorporó `oracle_distance_to_cell_edge_m`. Distancia geométrica desde el impacto del oráculo a la frontera de celda; **no** es error en profundidad ni precisión de GPU.

| Pose | Rayos con discrepancias representación↔GPU | A más de 0.1 mm del borde de su celda | Ejemplo |
|---|---:|---:|---|
| 0, pose original | 7 | 2 | (413,441): error −4.413 mm, a 0.183 mm del borde |
| 1, yaw −0.1° | 7 | 2 | (416,434): error **−191.415 mm**, a **0.2675 mm** del borde |
| 2, yaw +0.1° | 11 | 2 | (461,370): error −4.254 mm con **mismo propietario**, a 0.285 mm del borde |

Hay errores próximos a fronteras de celdas que podrían tener causas numéricas, pero **no todos los fallos pueden descartarse simplemente como impactos en el borde de la celda ganadora según el oráculo**. La segunda pose selecciona como ganador GPU a la superficie 80 a 2.690960059 m mientras el oráculo de celdas da como primer impacto a la superficie 83 a 2.882374825 m. La diferencia es 0.191414766 m; la GPU devuelve una superficie **más cercana** que la del oráculo, así que falta examinar si se trata de un oclusor espurio, una transformación/proyección incorrecta, o un error de intersección del propio oráculo cerca de la discontinuidad **de otra superficie**.

`oracle_next_candidate_gap_m` resultó nulo en los impactos registrados: el recorrido independiente histórico corta después del primer impacto por tramo y no dispone de un segundo candidato fiable en esos píxeles. **No atribuir esta causa a empate de profundidades sin desarrollar otro oráculo independiente de dos impactos y certificarlo.**

El informe `strict_sample_acceptance.passed = false` en todas las poses, aunque las verificaciones de ejecución Godot y el workflow CI finalizaron correctamente. **Éxito de ejecución ≠ exactitud geométrica**. Permanecen dos tareas independientes: arreglar las discrepancias de consulta frente a las celdas, y recuperar/verificar el original Blender para medir pérdida de captura frente a fuente.
