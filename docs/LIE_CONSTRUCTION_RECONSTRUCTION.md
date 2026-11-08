# Reconstrucción móvil: diagnóstico y corrección 6.1

## Evidencia física recibida

Poco 2412DPC0AG, Mali-G720 MC7, APK 6.0.1, escena `corner`, semilla
2102, 781 instancias y 1,165,568 muestras. Salida 960 × 960, reconstrucción
1920 × 1920. Los cuatro bloques contienen 24 eventos cada uno.

| Evento | Imagen GPU p50 / p95 (ms) | Campo GPU p50 (ms) | Intervalo de pantalla p50 (ms) |
|---|---:|---:|---:|
| Cámara, directa | 511.609 / 553.912 | Sin solve nuevo | 516.400 |
| Luz, directa | 513.957 / 545.636 | 2.158 | 523.491 |
| Cámara, dos rebotes | 516.708 / 534.065 | Sin solve nuevo | 522.029 |
| Luz, dos rebotes | 515.882 / 526.904 | 4.837 | 525.979 |

No sumar percentiles de intervalos distintos. Hay aproximadamente 1.9 imágenes
nuevas por segundo durante esta prueba, aunque una imagen residente puede
presentarse muchas veces. El recorrido de apariencia necesita una reducción
de aproximadamente 31 veces para entrar por sí solo en 16.67 ms. El comando
síncrono también tarda 50–57 ms de mediana; eso es tiempo transcurrido, no una
medición del porcentaje de utilización de CPU.

Las lecturas de páginas, siete subidas, identidad del campo y asignaciones
permanecen estables. La cámara no resuelve de nuevo el campo; cada evento de
luz sí produce un solve. No hay evidencia de que la lectura de fuentes o los
dos rebotes expliquen los 500 ms. El radio energético estaba desactivado y no
se midió una comparación con un renderer convencional. El estado térmico 0
no proporciona temperatura ni frecuencia de la GPU, que eran inaccesibles.

## Investigación y causas comprobadas en el código

1. `update_scene()` leía la receta, seleccionaba LOD, construía transformaciones,
   propietarios y paquetes de instancias para cada cambio de cámara o luz.
2. Una sola firma invalidaba proyección, profundidad, acumulación material,
   sombra fina y sombreado final. La imagen estaba almacenada únicamente como
   un resultado completo, sin conservar resultados intermedios independientes.
3. Cada banco despachaba todas las invocaciones y buscaba el trabajo global
   antes de rechazar las que pertenecían a otro banco.
4. Los splats recorrían un cuadrado completo; el descarte de profundidad en la
   acumulación ocurría después de transformar y comprobar soporte de fuente.
   Se expresaban búsquedas de rangos e inversas de instancia dentro del trabajo
   por píxel. El coste real de esas expresiones depende del compilador.

Estos son hechos del recorrido anterior. Sin tiempos por pase no se atribuye
una fracción exacta de los 500 ms a cada causa ni se promete una ganancia Mali.

Arm describe la contención entre operaciones atómicas sobre las mismas líneas
de caché y la presión de registros como riesgos en cómputo. La investigación de
Schütz y colaboradores muestra el valor del descarte temprano de profundidad
y de organizar el trabajo de puntos. No implica que sus cifras de GPU de
escritorio se transfieran a esta escena o a Android. La documentación reciente
de Arm también distingue qué ventajas del rasterizador de hardware se pierden
al trasladar visibilidad y sombreado a compute.

## Cambios

Se conserva una preparación CPU por geometría: escena, semilla, LOD, presencia
del obstáculo y pose de puerta. La receta y los paquetes se reutilizan en
cambios radiométricos o de cámara. Las transacciones siguen pasando por la
interfaz validada; se reutiliza la validación únicamente para bytes idénticos.

La reconstrucción mantiene dominios independientes:

| Cambio | Visibilidad y material de cámara | Sombra fina | Sombreado y salida |
|---|---|---|---|
| Giro de cámara | Recalcular | Conservar | Recalcular |
| Movimiento de luz | Conservar | Recalcular | Recalcular |
| Rebotes, radio o contribución indirecta | Conservar | Conservar | Recalcular |
| Nueva geometría o puerta | Recalcular | Recalcular | Recalcular |
| Sin cambios | Conservar | Conservar | Conservar |

Cambiar distancia o centro también mueve las luces en este laboratorio; por
esa dependencia existente puede invalidar ambos dominios. Invertir el orden de
bancos fuerza ambos recorridos para mantener válida la prueba de orden.

Cada banco recibe una lista compacta de trabajos con su prefijo local y la
dirección global original. Se conservan IDs de propietario, desempates de
profundidad y direcciones de proyección. La suma de muestras útiles no cambia;
se eliminan invocaciones de bancos ajenos. El almacenamiento añadido es de
16 bytes por trabajo, sin duplicar capturas. En `corner-2102` hay 753,664
muestras de ladrillo, 219,904 de mortero y 96,000 de cada uno de hormigón y
madera: 1,165,568 útiles. Antes se lanzaban 4,662,272 invocaciones por pase de
cámara para filtrar bancos; ahora se lanzan 1,165,568 más el redondeo de los
últimos grupos de 64 hilos. Esta reducción de invocaciones no equivale por sí
sola a una aceleración temporal de cuatro veces.

La cámara recorre intervalos conservadores de la misma elipse, con guardas y
las pruebas originales de soporte, recorte y caja de fuente. La acumulación
descarta candidatos ocultos antes de esas pruebas; la profundidad ya está
completa en este pase. No se introduce una lectura concurrente no atómica del
z-buffer durante la escritura de profundidad. La sombra limita sus candidatos
al viewport original. Inversa y rango de fuente se preparan por muestra.

No se cambian mapas, muestras, LOD seleccionados, resolución predeterminada,
potencias, propietarios o ecuaciones del campo. No se sustituyen los assets por
primitivas ni se desactivan rebotes, normales o sombras para aparentar rapidez.

## Validación y siguiente medición

Se contrastó además la unidad contra el backend Vulkan de Godot 4.7.2: el
resultado GPU se convierte desde timestamps en nanosegundos mediante
`timestamp_query_result_to_time`; el tiempo CPU usa otra unidad. La concordancia
con los intervalos físicos de aproximadamente medio segundo también descarta
interpretar el problema como una simple confusión ms/µs.

El informe automático añade intervalos de GPU por limpieza, sombra, proyección
y profundidad, acumulación material, sombreado y salida. Los marcadores rodean
listas de cómputo terminadas. No hay `sync`, lectura de texturas/búferes ni
espera de fence en el recorrido de medición. Un pase reutilizado no recibe un
tiempo cero inventado. Los contadores indican qué pases se ejecutaron realmente.

La comparación nativa ejecuta diez estados sobre el código fijado 6.0.1 y el
candidato, usando los mismos bancos. Comprueba profundidad y alpha bit a bit,
RGB con tolerancia de 1e-6 y la misma cantidad de muestras. Incluye el ángulo
bajo del informe físico, movimiento de luz y cámara, normales, abertura,
obstáculo, vista posterior, dos rebotes y radio energético. Las regresiones
existentes comprueban orden de bancos, fuentes, apertura de puerta, caché,
resolución, liberación y segunda instancia. Los resultados efectivos y los
negativos se registran en el checkpoint de la entrega.

El Vulkan de CI es software y valida corrección; no certifica FPS del Poco.
La mejora física y el objetivo de 60 FPS necesitan repetir el mismo benchmark
en el dispositivo. Si todavía domina acumulación o proyección, el siguiente
experimento debe medir agrupación por tiles y descarte de grupos de muestras,
con equivalencia visual independiente. No corresponde prometer esa mejora
antes de medirla ni cambiar simultáneamente la representación del material.

## Fuentes primarias

- [Arm: Mali GPU Best Practices, atomics](https://armkeil.blob.core.windows.net/developer/Arm%20Developer%20Community/PDF/Arm%20Mali%20GPU%20Best%20Practices.pdf)
- [Arm: Mali-G615 performance counters, load/store and atomics](https://arm-software.github.io/libGPUCounters/mali-g615_counter_reference.html)
- [Schütz y Wimmer: Rendering Point Clouds with Compute Shaders (2019)](https://www.cg.tuwien.ac.at/research/publications/2019/SCHUETZ-2019-PCC/)
- [Schütz et al.: Rendering Point Clouds with Compute Shaders and Vertex Order Optimization (2021)](https://www.cg.tuwien.ac.at/research/publications/2021/SCHUETZ-2021-PCC/SCHUETZ-2021-PCC-paper.pdf)
- [Arm: Mali and Unreal Engine’s Nanite (2026)](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/mali-and-unreal-engine-s-nanite-enabling-the-future-of-mobile-graphics)
- [Godot: RenderingDevice, marcadores y listas de cómputo](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html)
