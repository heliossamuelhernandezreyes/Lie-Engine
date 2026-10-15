# LIE38 — Integración auditada de WALL05/09/12 en la casa real

**Fecha:** 15 de octubre de 2026. **Estado:** prototipo experimental **validado por CI**, NO combinado a producción.

- [PR #55](https://github.com/heliossamuelhernandezreyes/Lie-Engine/pull/55)
- [Ejecución CI nativa aprobada 38723982792](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38723982792)
- Capturas PNG originales, A/B contacto: `docs/captures/lie36/`.
- Origen WALL04 autenticado: `f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da`.

## Integraciones reales

1. **WALL05 — caché independiente por dependencia.**
   En `gpu_compute/lie36_house_effect.gd` se separan firmas de geometría de cámara, luz, grafo y sombreado. El banco captura sigue siendo un recurso común GPU con leases `lie_shared_sample_buffers.gd`.
   * Cámara: despeja y reproyecta, pero **reutiliza el grafo de paneles**.
   * Cambio de intensidad/color: solo pases **[8,10,4,6,11,12,7]**.
   * Cambio de posición/dirección de luz: [14,13,8,10,4,6,11,12,7]. Fases **14/13** regeneran únicamente el mapa de sombras, sin escribir profundidad de cámara, propietarios, normales acumuladas o proyectos ya residentes.
   * Cambio de exposición: **[7]**, sin reproyección, transporte o nueva sombra.
   * Cambio nulo: no envía trabajo de reconstrucción.
2. **Contrato de assets compartido LIE 0.9.**
   `tools/lie36_house_stage.py` invoca directamente `tools/lie_asset_contract.inspect_bank` para verificar SHA, normales, radios, materiales, soporte de caras e índices de LOD; escribe `asset-contract.json`. El cargador común `lie_asset_catalog.gd` valida los asset IDs derivados del SHA y de los rangos de muestras al iniciar Godot. `source-ids.bin` identifica cada registro real WALL04 usado en las cuatro variantes arquitectónicas.
3. **WALL09 — perfilador GPU reutilizable.**
   `lie_gpu_pass_profile.gd` registra timestamps nativos por fase del propio RenderingDevice: proyección, rasterización, grafo, rebote, respuesta GGX, reparación y salida. Son milisegundos de **llvmpipe por software**, nunca se presentan como tiempos GPU móvil ni FPS de un juego.
4. **WALL09 — contacto corto usando superficies capturadas.**
   `lie_contact_surface.glslinc` se reutiliza sobre testigos propios de la cámara (ganadores reales del banco, posición/normales originales), no sobre imágenes generadas ni huecos recuperados. Se controla con `microcontact`, **apagado por defecto** hasta medir calidad/temperatura en Android. Distancia 25 mm, bias 0.3 mm y 12 pasos. Encendido y apagado modifican píxeles RGB, pero no su alfa, LOD ni reconstrucción.
5. **Corrección adicional de uniones.**
   La reparación de huecos de un píxel dejó de depender del **color iluminado**. Acepta únicamente testigos de profundidad, normal y material capturado compatibles. Así, mover las luces ya no hace aparecer o desaparecer píxeles reconstruidos. La opción conserva la posibilidad de desactivar el cierre para comparar.
6. **Herencia verificada.**
   Se conservan la selección de WALL04 auténtico, el BRDF GGX/Smith/Fresnel y el recorte de elipses de WALL12, los 113 módulos arquitectónicos, LOD 15/60/38, el rebote RGB orientado de LIE37 y el apagado de rebotes/reparación para experimentos A/B.

## Evidencia (CI 38723982792)

- **4/4** pruebas Python, **50/50** comprobaciones Godot nativas; ninguna excepción.
- **113** instancias; **724.600** invocaciones reconstruidas; banco derivado de **110.800** muestras auténticas; **6.787** enlaces de transporte entre paneles, **0** excedentes de normalización detectados.
- El grafo se calculó **una vez para tres cámaras** diferentes.
- Cambiar potencia de luz preserva geometría y grafo. Mover la fuente conserva la geometría y reconstruye solo sombra + shading.
- Exposición solo reejecuta el pase 7.
- A/B cache frente a reconstrucción completa: **error máximo absoluto RGB/alpha 0.0**, en la vista evaluada.
- Contacto real ON/OFF: **5.830 píxeles RGB diferentes, alfa exactamente igual** para la captura de patio.
- Cobertura tras reparación geométrica: **90.137** píxeles fachada; **100.582** esquina; **94.839** patio a salida 512².
- Memoria solicitada al RenderingDevice: **178.465.792 bytes**, no RAM de proceso ni VRAM física medida.

### Perfil llvmpipe — solo como comprobación de fases

Instantáneas GPU por pase (4 muestras de contexto análogo, 512 interno); p50:

| Fase | GPU llvmpipe p50 |
|---|---:|
| Proyección y mapa de sombras | 114.025 ms |
| Rasterización | 118.874 ms |
| Grafo de conexiones | 6.596 ms |
| BRDF/material | 18.956 ms |
| Reparación | 8.617 ms |
| Salida/exposición | 2.957 ms |

Estas cifras **NO** son tasas de fotogramas ni una comparación de hardware con UE5. Los cachés omiten trabajo: no convierten por sí solos la proyección de 114 ms en un pase de 0 ms cuando **la cámara sí se mueve**.

## Qué no se ha integrado y por qué

- **WALL10/11 BVH+TLAS y visibilidad persistente por muestra:** los paquetes actuales contienen instancias y hashes **de la pared fija de 96 ladrillos**, no de los 113 paneles dinámicos de la casa. Copiarlos sin recompilación sería incorrecto; hace falta crear el BLAS/TLAS de maestros auténticos y hacer invalidación incremental cuando se cambien transformaciones o se destruyan elementos.
- **WALL12 iluminación completa por 872 nodos:** ese grafo CSR es de UNA pared; LIE37 aún usa un rebote *aproximado* a nivel de paneles y un grafo denso con coste de construcción O(P³). Se requiere un grafo mundial CSR transformado por instancia, no simular que el grafo existente sirve para cualquier edificio.
- **Prefab neutral WALL05 en vez de panel submuestreado WALL04:** la casa sigue usando cuatro subbibliotecas auténticas recortadas de una pared, no todavía el banco neutral y las 96 poses originales como un activo compilado de construcción. Hay que crear el nuevo ABI para muro compuesto con puerta/ventana/jambas antes de migrar toda la casa.
- **LIE22 destrucción/fragmentos:** prototipo útil; aún no hay colisión ni física estructural en esta casa, ni una invalidación de sus cachés por fractura.
- **Segundo o más emisores independientes:** el laboratorio actual conserva un único emisor directo; la infraestructura de 8 luces se puede reutilizar una vez que su grafo sea de mundo.
- **Rendimiento Android:** CI usa GPU Vulkan **llvmpipe** (CPU software), no el Poco. No afirmar 60 FPS en la casa, ahorro térmico ni calidad comparada con UE5.
- **Fidelidad arquitectónica final:** aún hay granulado, huecos, bordes poco convincentes, cubierta derivada de mampostería y jambas incompletas. Que la prueba pase no significa que la casa sea fotográfica.

**Próxima integración que sí cambia la estructura del motor:** prueba A/B controlada de dos muros perpendiculares hechos directamente con *maestros neutrales* WALL05 y mortero fotográfico, con BVH/TLAS de superficies reales recompilado desde las instancias. Convertirla en prefab de esquina reutilizable antes de multiplicarla a todos los edificios.
