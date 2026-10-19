# Auditoría integral del recorrido de LIE

Código auditado: `2decee6c97c69e49549d479eb122537774f2a9fc`.
Esta revisión no modifica el renderizador ni presenta otra optimización como
aceptada. Separa hechos del código, mediciones históricas del teléfono y lo
que todavía necesita una prueba causal. Los datos están en
`checkpoints/LIE_RENDERER_STATIC_AUDIT.json` y
`checkpoints/LIE_CAMERA_RENDER_MALI_2_1.json`.

## Diagnóstico estructural

La unidad física simple no es la unidad de trabajo visual. Una caja invisible
organiza colisión, límites y transformaciones; no convierte automáticamente
el contenido en seis consultas de imagen. El consumidor actual reconstruye
una superficie desde muestras XYZ con radio y normal: surfels. Resuelve sus
huellas solapadas con compute, rellena huecos y calcula iluminación propia.

Se ha optimizado reiteradamente esa ejecución sin cerrar primero la comparación
arquitectónica. Los experimentos anteriores conservaron muchos comportamientos
y fallos útiles, pero no demuestran que este contrato de representación sea
competitivo con un renderizador convencional para la misma pared y calidad.

### Hechos verificados en el código

| Trabajo | Evidencia | Consecuencia |
| --- | --- | --- |
| LOD0 contiene 384.000 referencias de ladrillo y 151.670 de mortero: 535.670 en total antes de selección GPU | `gpu_compute/assets/lie_wall04/catalog.json`, `tools/lie_wall05_shared.py` | Una pared con un solo collider sigue teniendo un presupuesto visual de cientos de miles de muestras |
| El LOD se elige por `distance_factor`, no por tamaño proyectado o resolución interna | `gpu_compute/lie_brick01_lab.gd`, `_apply()` | En el informe 2.1, distancia 1.0 conserva LOD0 al pasar de 1080 a 720; la selección GPU posterior puede reducirlo |
| La muestra fuente ocupa 80 bytes y el registro proyectado 96 bytes | `lie_wall17_stage_02.glsl`, estructuras `Sample` y `Projection` | Si se proyectara todo LOD0, solo escribir esos registros produciría 51.424.320 bytes; no es tráfico medido ni se supone que todos los registros se despachen |
| La etapa 2 proyecta y recorre las huellas para calcular profundidad; la 3 recorre las huellas otra vez | `lie_wall17_stage_02.glsl`, `lie_wall17_stage_03.glsl` | El coste depende de la suma de huellas/candidatos y del solapamiento, no solo de los píxeles finales |
| Cada contribución aceptada de material ejecuta ocho `atomicAdd`; profundidad y propiedad usan operaciones atómicas adicionales | `lie_wall17_stage_03.glsl` | Varias muestras pueden disputar las mismas direcciones. El número real de contribuciones y la contención todavía necesitan contadores |
| El filtro de material examina una vecindad 3×3 | `lie_wall17_stage_14.glsl` | Varias lecturas de proyecciones/material por píxel con propietario |
| La recuperación busca soporte 5×5, puede buscar mortero 13×13 y usa hasta 15×15 para reunir soporte | `lie_wall17_stage_08.glsl` | Los huecos no son gratis; cámara reconstruye esa información. Son límites de bucles, no cantidades efectivamente leídas por todo píxel |
| La visibilidad recorre TLAS/BLAS y prueba intersecciones con discos en GLSL | `lie_wall17_stage_11.glsl` | Trazado manual por compute. Los oclusores se mantienen fuera de cámara, correctamente, pero su coste permanece |
| La composición calcula una base y luego sustituye su término directo por uno detallado | `lie_wall17_stage_04.glsl`, `lie_wall17_stage_10.glsl` | Se leen grupos de hasta nueve nodos y se resuelve una respuesta por luz; conviene revisar el contrato entero en vez de sumar otra corrección al final |
| Búferes de experimentos desactivados siguen asignándose | `lie_wall22_tile_effect.gd`, `_make_set()`; informe 2.1 | 39.292.744 bytes de tiles desactivados y 16.680.224 de vista compacta desactivada en ese informe. Es memoria solicitada, no prueba de un cuello de ancho de banda |

En la ruta compute normal, con los interruptores del informe y límites del mundo
ya residentes, una reconstrucción de cámara contiene nominalmente estos 13
despachos, separados por dependencias:

`clear → surface_select → project/depth → raster/material → visibility_compact
→ material_filter → fused_base → recovery_build → visibility_keys
→ visibility_invalidate → world_visibility → surface_light → output`.

Construir los límites añade `surface_bounds` y `surface_parents`. El número de
despachos no demuestra que sus barreras sean el coste dominante. Tampoco se
cuentan helpers presentes pero no alcanzables en un shader como trabajo real.

## La evidencia física que ya existía

`checkpoints/LIE_VISIBILITY_STREAM_MALI.json` transcribe una prueba del mismo
Mali-G720, LIE 1.6, el 16 de octubre. Al mover la luz:

- intervalo total de referencia p50: 42,237 ms;
- `world_visibility` de referencia p50: 30,252 ms;
- en tres capturas de trabajo instrumentadas aparte: aproximadamente
  4,74–4,81 millones de nodos BLAS, 1,99–2,01 millones de nodos de escena y
  2,10–2,15 millones de pruebas de disco.

La razón de esas dos medianas es aproximadamente 72%; no es una atribución
pareada por evento. Los contadores proceden del modo stream y no de los
intervalos temporizados de referencia. No se trasladan esos porcentajes a 2.1.
Sí constituyen evidencia histórica concreta de que las consultas geométricas
de sombras podían dominar al mover una luz. Un renderizador convencional de
sombras por mapas está resolviendo ese problema de otra manera.

En ese mismo informe, cámara tenía 52,307 ms totales y 6,721 ms de visibilidad.
Por tanto, tampoco es válido reducir todo el problema de LIE a las sombras:
el coste dominante cambia con el tipo de actualización.

## Qué establece realmente el informe 2.1

La prueba nueva tiene 108 eventos esperados y registrados, cuatro rondas y
12 muestras por grupo; finaliza sin error y restaura el estado. Los 36 eventos
gráficos se excluyen explícitamente: el driver no expone mezcla R32F/RGBA32F.
No hubo trabajo gráfico ni asignación de sus attachments. Eso rechaza el
diseño MIN/ADD concreto, no todas las rutas gráficas posibles.

| Cambio | 1080 p50 ms | 810 p50 ms | 720 p50 ms |
| --- | ---: | ---: | ---: |
| Cámara | 44,661 | 37,377 | 33,932 |
| Potencia | 10,747 | 6,629 | 4,819 |
| Posición de luz | 40,253 | 29,417 | 27,606 |

Reducir 55,56% de píxeles reduce cámara 24,02%, potencia 55,16% y posición
31,42%. Hay trabajo que no escala proporcionalmente al número de píxeles.
No se obtiene de estos tres puntos un suelo físico demostrado de milisegundos.
Mover la luz conserva la geometría residente y sigue siendo costoso; es otra
razón para no atribuir toda la demora al raster de muestras.

No se puede restar directamente la mediana de posición a la de cámara para
medir geometría: los eventos, estados de caché y tareas son diferentes. Tampoco
se puede comparar 44,661 ms con los 59,79 ms de 2.0 como mejora del código:
el encuadre y la distancia cambiaron. La rama 2.1 conserva la ruta compute1080.

`hardware_status=not_probed` y `stage_timestamps=false` impiden atribuir los
tiempos actuales a una etapa o unidad funcional concreta. El tiempo CPU del
control no es todo el coste del motor; `godot_process` no se suma al tiempo GPU.
Los 2,815 ms del viewport tampoco constituyen una referencia convencional
comparable: la captura incluye cuadros con imagen LIE reutilizada.

## Defecto concreto encontrado al revisar el recorrido entero

La etapa de borrado tiene dos dominios: píxeles y referencias de muestras.
`lie_wall05_shared_effect.gd` la despacha con
`max(render_size², 512²)`, mientras que la etapa 1 también debe inicializar
`source_visibility[i]` para `i < parameters.counts.x`.

Con LOD0 y tamaño 720, el despacho tiene 518.400 invocaciones y el dominio de
referencias tiene 535.670 elementos. El múltiplo de 64 no añade padding aquí.
Quedan **17.270 slots sin visitar**. Las etapas de raster y compacción usan esos
flags para crear trabajo de visibilidad; el límite se debe corregir para
cubrir todos los dominios. El impacto exacto en imagen/cola depende de qué
referencias sobrevivan y del historial. No se afirma que explique los 34 ms ni
que ya se haya reproducido un artefacto en el teléfono.

Antes de aceptar una corrección: comprobar el borrado de todo el rango en
Vulkan, transiciones 1080→720→720, ganadores en la cola de referencias final,
cambios de luz después del resize y equivalencia de visibilidad respecto de
recomputar desde cero. Esta auditoría registra el defecto; no modifica el
renderizador sin esas comprobaciones.

## Por qué un motor puede dibujar algo más complejo con menor coste

La apariencia visible no cuenta operaciones. El pipeline convencional usa
geometría conectada y texturas, rasterización/interpolación/profundidad de la
GPU, filtrado de texturas y mecanismos de descarte antes de sombrear cuando
son aplicables. Una superficie extensa puede compartir muchos atributos y
consultar mapas de detalle, en vez de reconstruirlos con contribuciones
atómicas de muchos puntos. Sombras por mapas tampoco equivalen a recorrer
nuestros discos capturados por receptor/luz.

Esto no significa que compute o los puntos sean intrínsecamente lentos:
existen rasterizadores compute rápidos para nubes de puntos. Sus cargas y
restricciones importan: el trabajo de Schütz 2022 citado abajo se centra en
puntos de un píxel, y no certifica nuestras elipses, recuperación e iluminación.

Cambiar GDScript por C++ no cambia estos kernels, que ya se ejecutan en GLSL
sobre Vulkan. Quitar Godot puede cambiar la integración y sincronización, pero
no elimina automáticamente ninguno de los recorridos descritos.

## Corrección global y prueba causal

La decisión arquitectónica pendiente es qué debe costar construir un píxel:
mantener la representación densa actual con un límite de trabajo competitivo,
o compilar las capturas fuera de ejecución a superficies/capas consultables
por caja, con profundidad, normales, material y niveles de detalle. La segunda
opción exige validar desoclusiones, huecos reales, siluetas y relighting; seis
fotografías RGB o una caja por sí solas no resuelven esos requisitos.

La comparación que debe preceder otra variante de producción es una batería
única a cámara, resolución, banco y luces fijos:

| Caso | Pregunta causal | Precaución |
| --- | --- | --- |
| Viewport vacío y presentación de una imagen residente | ¿Cuánto cuesta el entorno sin reconstrucción? | Forzar eventos comparables; distinguir GPU, CPU y presentación |
| Referencia convencional de la misma pared | ¿Qué cuesta la solución que tratamos de mejorar? | Misma resolución/cámara, materiales y alcance de luces; declarar sombras/GI diferentes y comparar imágenes |
| LIE profundidad/material sin recuperación ni luz | ¿Cuánto paga el rasterizador de muestras? | Ablación de diagnóstico; sus imágenes incompletas no son una mejora de calidad aceptada |
| LIE con recuperación, sin refinamiento/visibilidad fina | ¿Cuánto añade reconstruir cobertura? | Misma secuencia y cachés controladas |
| LIE con refinamiento, sin consultas geométricas finas | ¿Cuánto añade el sombreado? | No presentar quitar sombras como aceleración equivalente |
| LIE completo, cachés frías y calientes | ¿Qué añade la visibilidad y cuál es el coste real final? | Tiempos por etapa y exterior; no sumar diferencias de medianas como si fueran costes exactos |
| Mismo núcleo en un visor Vulkan mínimo, si queda una brecha atribuible a integración | ¿Cuánto se gana quitando Godot con trabajo idéntico? | No cambiar a la vez representación, precisión, resolución o caché |

Registrar conteos de muestras seleccionadas, candidatos, contribuciones,
ganadores únicos, recuperación y visitas/pruebas de sombras, además de tiempos.
Tomar contadores instrumentados en ejecuciones separadas del rendimiento sin
instrumentación. Conservar todos los eventos, picos y estados iniciales.

La refactorización resultante debe retirar trabajo redundante del recorrido,
elegir una política coherente de cobertura/material/visibilidad y dejar los
experimentos desactivados fuera de la asignación normal. Su aceptación depende
del coste total y la calidad/movimiento de referencia, no de que una etapa
aislada sea más rápida. Hasta ejecutar la prueba equivalente en el dispositivo,
no se promete una aceleración global ni se identifica una instrucción concreta
como responsable de todos los milisegundos actuales.

## Referencias primarias

- [Arm: análisis de cargas, visibilidad y overdraw](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/finding-and-fixing-hidden-performance-problems-in-mobile-games-with-arm-performance-studio).
- [Vulkan: rasterización](https://docs.vulkan.org/spec/latest/chapters/primsrast.html).
- [Vulkan: profundidad](https://docs.vulkan.org/guide/latest/depth.html).
- [Schütz et al., Software Rasterization of 2 Billion Points in Real Time](https://www.cg.tuwien.ac.at/research/publications/2022/SCHUETZ-2022-PCC/SCHUETZ-2022-PCC-paper.pdf).
