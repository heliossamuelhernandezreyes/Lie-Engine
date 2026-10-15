# Auditoría de reutilización de LIE para la casa — 2026-10-15

**Rama auditada**: `experiment/lie36-real-scan-house`, base de `work/lie-material-light` (WALL12 / 0.9.0); serie de PR #40–#55. Este documento **no modifica código ni da por integrada** ninguna mejora nueva. Inspección de la implementación, contratos, pruebas y documentos de resultados del repositorio.

## Hallazgo principal

LIE36/37 fue útil para validar una casa con muros fotografiados y un rebote RGB, pero su arquitectura **duplica o simplifica** varias funciones probadas de WALL05–WALL12. **No es correcto seguir añadiendo efectos visuales al shader de LIE37 como ruta principal**. Hay que generalizar el motor existente para múltiples maestros/instancias y reutilizar los prefabs constructivos.

## Inventario de componentes reutilizables

| Componente | Ruta fuente | Veredicto | Por qué |
|---|---|---|---|
| Banco neutral de ladrillo real + mortero PBR capturado | `gpu_compute/assets/lie_brick02`, `lie_mortar01`; `docs/LIE_WALL05_SHARED_OPTICAL_ANDROID.md` | **Reutilizar como fuente canónica** | WALL05 guarda 281.000 muestras de un ladrillo y 240.257 del mortero; 41.700.560 B y tabla de referencias, para 96 instancias. El precompuesto WALL04 (61.767.760 B) es referencia exacta, no el mejor formato para miles de muros. |
| Pared preensamblada original de 96 ladrillos / 8 hiladas | `gpu_compute/assets/lie_wall04/catalog.json`; `tools/lie_wall04_compose.py` | **Prefab de referencia y control visual** | Su montaje, juntas y zonas tienen identidad comprobable por SHA, pero un edificio exige transformar/instanciar los ladrillos y sus morteros, no volver a recortar 20.000 puntos de una pared entera. |
| Captura de assets + contrato de identidad | `tools/lie_asset_capture.py`, `tools/lie_asset_contract.py`, `gpu_compute/lie_asset_catalog.gd`, `lie_sample_identity.gd` | **Reutilizar directamente y ampliar ABI** | IDs estables `banco + maestro + LOD + muestra + instancia`; validar radios, normales, pivotes, orientación y formato de 80 B, además de procedencia. |
| Banco GPU compartido y leases | `gpu_compute/lie_shared_sample_buffers.gd` | **Reutilizar directamente** | Una carga por banco/dispositivo con recuento de referencias y generación; escrituras y cachés por consumidor. No duplicar bancos para cada muro. |
| Envolventes, escalado, puertas, ventanas, esquinas y piezas | `docs/LIE_28_MODULAR_BUILDING.md`, `tools/lie28_prepare_blender.py`, `gpu_compute/lie28_building_lab.gd` | **Reutilizar la gramática constructiva** | LIE28 ya tiene módulos de muro, esquinas, marco superior/ventana, losas, cubierta, instancias y coordenadas. **No reemplazar el ladrillo escaneado con sus texturas de demostración.** |
| BRDF y rasterización optimizada 0.9 | `gpu_compute/shaders/lib/lie_opaque_brdf.glslinc`, `lie_splat_work.glslinc`; `lie_wall12_material_effect.gd` | **Reutilizar directamente** | GGX/Smith/Fresnel, rugosidad de fuente, filtrado de normales y recorte conservador de elipses. Resultado WALL12: 26–31% menos *comprobaciones candidatas*, no FPS medidos en Android. |
| Perfilado por pases | `gpu_compute/lie_gpu_pass_profile.gd`, `lie_wall09_shared_effect.gd` | **Reutilizar directamente** | Métricas GPU con identificadores de pase y timestamp; separar geometría, raster, transporte, sombras, recuperación y salida. |
| Cachés separadas de geometría, luz y exposición | `gpu_compute/lie_wall05_shared_effect.gd` | **Adaptación prioritaria** | WALL05 compara firma geométrica independiente de parámetros luminosos; reconstrucción en movimiento, relighting sin reproyección, exposición sin sombrear. LIE37 actualmente ejecuta 11 fases de nuevo si cambia la firma completa. |
| Visibilidad 3D real de muestras | `gpu_compute/shaders/lib/lie_source_visibility.glslinc`, `lie_source_surface_loader.gd`, `lie_shared_visibility_buffers.gd` | **Adaptar BLAS/TLAS al mundo de casa** | BVH de discos tangentes capturados; instancias con transformación afín, sin depender de cámara. Adaptador original tiene TLAS **estático**, debe actualizarse al mover/destruir partes de la casa. |
| Identidad persistente + caché de sombra por fuente | `gpu_compute/lie_wall11_persistent_effect.gd`, `lie_shared_shadow_cache.gd`, `shaders/lib/lie_persistent_visibility.glslinc` | **Adaptar** | Ocultar/alumbrar superficies sin reconsultar cada vez en todas las cámaras; invalida por luz y escena, no por vista. Hay dominios fijados por SHA del banco/BLAS/TLAS originales. |
| Transporte RGB de hasta 8 fuentes y CSR | `gpu_compute/lie_light_field_transport.gd`, `lie_surface_light_transport.gd`, `shaders/lie_light_field.glsl` | **Adaptar** | Separación por emisor, radios, áreas, absorción, recibidores y rebotes. El grafo debe regenerarse cuando cambien posiciones/visibilidad (inicialmente offline + caché; más adelante incremental). |
| Ley pasiva de emisión angular | `gpu_compute/shaders/lib/lie_passive_scatter.glslinc` + `lie_wall05_optical_transport.gd` | **Reutilizar con límites explícitos** | Reparto por albedo/rugosidad/dirección con normalización y radio; **no** es GGX físicamente exacto ni vidrio refractado en la escena. |
| Contactos y recuperación basados en testigos reales | `shaders/lib/lie_contact_surface.glslinc`, `lie_irradiance_stencil.glslinc`, `lie_wall10_source.glsl` | **Adaptar con dueños de instancia** | Mejor que la regla LIE37 de dos píxeles/normal similar: valida muestra original, profundidad, testigo de grupo y continuidad de normales. Recuperación no debe crear geometría inexistente. |
| Daño local / sustitución de módulos | `gpu_compute/lie22_modular_lab.gd`, `docs/LIE_22_MODULAR_MASTERS.md` | **Reutilizar después de la calidad visual** | 48 ladrillos, 12 módulos, daño por celda y fragmentos físicos. Es un **prototipo**, no un sistema universal de fractura fractal para edificios. |
| Escaneo de edificio completo | `gpu_compute/assets/lie34`; `docs/LIE_34_REAL_SCAN_CAPTURE.md` | **Referencia independiente, no sustituto** | Es otra fuente fotogramétrica de fachada/edificio, **no** el maestro de ladrillo autorizado de WALL04. No mezclar ambas identidades sin registrarlo. |

## Lo que hay que dejar de usar como arquitectura final

1. `tools/lie36_real_house.py` actualmente transforma WALL04 entero a cuatro paneles `brick/window/door/slit` seleccionando 20k/6k/1.7k muestras y ensanchando huellas. Se preservan XYZ/normales/RGB de cada muestra elegida, pero **no la densidad ni las relaciones de todos los ladrillos originales**. Para esquinas/jambas ni hay capturas fuente adicionales: se recortan puntos.
2. `gpu_compute/lie36_house_effect.gd` recalcula proyectar/rasterizar/transportar/sombrear/cerrar huecos en cada cambio de firma. WALL05 ya demuestra firma de geometría y luz separadas. 11 pases por cambio de cámara/luz no es una estrategia de escalado.
3. `gpu_compute/shaders/lie36_house_material.glsl` usa centros de panel y planos, no el BVH de discos capturados. Usa valores absolutos del coseno, por lo que permite transferencia por ambas caras aun cuando el material debería ser unilateral. El albedo del panel proviene de **tres muestras** del banco. Los 6.787 enlaces y la pasividad del cálculo prueban que se ejecuta y está acotado; **no** prueban visibilidad o transporte fotométrico realista.
4. Cada fase de enlaces de `lie36_house_material.glsl` itera fuentes × destinos × posibles bloqueadores: coste teórico **O(P³)**. El límite `PANEL_CAP=128` contiene ese crecimiento, pero la casa ya tiene 113 paneles. Además `MAX_WORK=750000` y la escena consume 724.600 invocaciones (**96,6% del presupuesto**). No se puede crear un interior grande con este límite sin jerarquía.
5. La recuperación LIE37 basada en vecinos opuestos subsana 1.130/1.149/993 píxeles según la vista, pero no reconstruye la verdadera junta, huecos amplios, grosor, jambas o caras nuevas. Una subida de cobertura **no** equivale a una subida comprobada de fotorrealismo.
6. La apariencia LIE37 es de laboratorio `512×512`, usando un rebote difuso de panel, no WALL12 con 1080×1080 interno / 720 salida, 872 nodos y sombras reales de microrrelieve. Comparar tiempos/búferes de ambos no es una prueba válida de superioridad.
7. `lie_wall04_transport.gd` valida un grafo CSR generado de **872 nodos de la pared concreta** con clave de geometría inmutable. `lie_wall12_material.glsl` contiene supuestos de 96 ladrillos, 97 consumidores y layout de cursos. **No copiar esos shaders directamente**; extraer funciones comunes y generar nuevos índices/grafo de edificio.

## Resultados auditables disponibles

- LIE-37 (GitHub Actions `38718214216`): 29 comprobaciones Godot y 4 tests Python; 113 instancias, 724.600 invocaciones, 6.787 enlaces, 112 paneles con rebote, 0 violaciones medidas del presupuesto de pesos; diferencias A/B en luz y costuras; 178.465.792 bytes de búferes solicitados. GPU de prueba: **llvmpipe**, no móvil.
- WALL12: gráficos a 1080 interno, 535.670 invocaciones capturadas originales y ~252 MB de bufers de apariencia más ~1,54 MB de transporte. Optimización de 26–31% de candidatos de raster; 48 casos de material y 43 comprobaciones de pared, con regresiones A/B. **No se ha demostrado FPS sostenido ni consumo térmico en el Poco de esta versión**.
- WALL10: jerarquía BLAS+TLAS sobre discos auténticos, reutilizable entre dos cámaras en la escena original; TLAS de escenas estáticas.
- LIE22/LIE28: sistemas ya probados de edificios modulares y daño local, aún no integrados con WALL12 de alta fidelidad.

## Orden de trabajo propuesto — sin tocar el maestro

**P0. Prefab real:** construir un ABI `master_id + instance_transform + source_id + lod` que monte una casa desde el ladrillo neutral WALL05 y el mortero, no desde un submuestreo de un muro entero; preservar cursos, juntas, grosor y esquinas. Crear un módulo de pared compatible con dimensiones reales, versiones puerta/ventana con jambas y dinteles auténticos o documentar explícitamente que son prototipos.

**P1. Caché independiente por dependencia:** incorporar firmas geométricas, de fuente y exposición de WALL05; no proyectar nuevamente si cambia únicamente la luz; no reconstruir el grafo espacial si cambia la cámara. Pruebas de reconstrucciones y transferencias antes/después.

**P2. Visibilidad 3D compartida:** usar BVH de muestras + TLAS instanciado de WALL10/11 para evitar sombras de plano infinito, ocultar contactos reales y respetar aperturas. Mantener invalidación por transformación y por daño.

**P3. Transporte RGB mundial:** crear CSR de receptores/emisores por **superficies reales transformadas**, integrar los pases de `lie_light_field_transport.gd` y sus presupuestos, separar luz directa GGX de indirecta difusa sin doble contabilización. Sustituir coste cúbico por conexiones espaciales relevantes y caché geométrica.

**P4. Recuperación de cobertura:** adoptar la búsqueda de testigos de WALL12 para coser solo regiones compatibles según dueño/normal/profundidad; comparar con render denso de las mismas muestras y evitar rellenar huecos deliberados.

**P5. Benchmarks de verdad:** fijar cámara, resolución, luz y fuente de datos entre una pared WALL12 sola y la misma pared instanciada en la casa; comparar cobertura, color, geometría, coste de proyección, sombreado, transferencias, memoria, 60 segundos de movimiento y teléfono real. Aceptar mejora solo con capturas nativas y pruebas A/B. Registrar fallos.

**P6. Integración gradual de LIE22:** las aperturas no equivalen todavía a destrucción; actualizar grafo, TLAS y caches solamente para las piezas destruidas una vez se valide la calidad de la casa intacta.

## Veredicto

El **cuello de botella es de integración, no de ausencia de tecnología**. Para conservar la fidelidad del maestro, el siguiente paso debe ser una escena de prueba con **dos muros perpendiculares hechos de instancias auténticas WALL05**, con luz y visibilidad de WALL12 y una esquina verificable. Si supera controles de fuente, iluminación, continuidad y coste, entonces escalarla a toda la casa. No declarar una mejora de calidad sin capturas reales y benchmarks.
