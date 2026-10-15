# LIE 1.2 — superficies activas y preparación CPU

Base: 4b27d8a50063d6870ec0a44602d6acbe1f7fb502; runtime 1.1 validado
604da39237307d410f07d1f9f758e4ed80fa1b05. Objetivo autorizado: optimizar
visibilidad al mover luces, preparación CPU y reconstrucción al mover cámara,
conservando detalle, bancos, materiales y comportamiento luminoso.

## Evidencia del Poco

Los dos informes del usuario son parciales: no se reconstruye un JSON completo
que no fue recibido. Se conservan sus valores relevantes en el checkpoint.
Mali-G720 MC7, 1080 interno, dos canales físicos. Uso manual: suma GPU mediana
33.07 ms / p95 45.18; recuperación 5.806, raster 5.176, proyección 4.789.
En el diagnóstico de tres eventos por tipo: mover luz cuesta 42.658 ms GPU
mediana y visibilidad 27.986 (66% de suma de medianas de etapas). Los comandos
CPU de cámara/potencia/posición dan medianas 12.950/25.357/27.756 ms.
Son ventanas/casos diferentes, no un ensayo térmico sostenido ni 48/55 FPS de
imágenes nuevas. Se evita convertir ahorro de instrucciones en FPS prometidos.

## Resultado aceptado

Runtime final: `fbe2e0e6fd4b21980acf52205f30d8359436ad4e`. Las 23 ejecuciones CI
de ese commit pasaron, incluida la dedicada 38773049005, job 116553552122.
Godot 4.7.2: 16 comprobaciones de paquetes/lotes, 18 de comandos, 126 de trazas
GPU contra referencias y 59 del runtime Mobile. También pasaron los controles
y regresiones anteriores, rig CPU 247 y sesión de agente 25. Evidencia completa:
`LIE_ACTIVE_VISIBILITY_NATIVE.json`, `LIE_ACTIVE_TRACE_NATIVE.json` y
`LIE_1_2_ANDROID_ACCEPTANCE.json` en checkpoints; se conserva aparte la primera
aceptación de a85bed12 y su artifact verificable.

La compacción conserva profundidad exactamente y cobertura IoU 1.0. La mayor
diferencia de color al habilitar el recorrido de cajas fue 7.701e-7; la cola
sola dio diferencia cero en las tres vistas. Ocho canales de área: diferencia
cero. La copia del diagnóstico real conserva sus tres grupos/nueve eventos
en menos de 16 KiB. Memoria RID solicitada: 254,994,920 bytes, incluyendo
3,000,016 bytes nuevos de cola. No es una lectura de VRAM ni de PSS Android.

Medianas de tres eventos por modo en **llvmpipe sobre CPU de CI**, en ms:

| Medición | Comparación OFF | Optimizado ON |
| --- | ---: | ---: |
| Comando CPU de cámara | 4.311 | 0.564 |
| Comando CPU de potencia | 6.982 | 0.644 |
| Comando CPU de posición de luz | 7.092 | 0.647 |
| GPU de posición: suma de etapas | 352.731 | 313.662 |
| GPU de posición: solo visibilidad | 227.196 | 189.535 |
| GPU de potencia: suma de etapas | 132.376 | 133.894 |

No son tiempos del Mali ni un ahorro universal: el caso GPU de potencia no
mejoró en esa ventana. Las muestras GPU de cámara tienen historial de caché
que evoluciona entre modos; no se usan como comparación controlada de rapidez.
Los rayos fríos de la vista 12° pasan de 80,577 a 80,547 por luz: la cola evita
principalmente invocaciones vacías, no elimina masivamente rayos que ya eran
necesarios. La aceleración del recorrido se mide aparte y tiene interruptor.

APK ARM64 `LIE-Eficiencia-1.2.0.apk`: 58,146,618 bytes, firmas v2/v3 válidas,
package `org.lieengine.wallruntime.v120`, versionCode 12. SHA-256:
`72663242951722d92ac7cf7a34027890d50159641a86420b0ea967ff4d1e8ebd`.
La descarga se comprobó contra el metadata de exportación y se verificó el
banco inmutable dentro del ZIP. Artifact 11993045866; SHA-256 de su ZIP:
`fbcac45923dd6bdb71b44069a8766acb2eec08807f66f8e0a190ac64a4c12e2d`.
La prueba física en Poco permanece pendiente; la APK y los JSON lo declaran.

## Preparación CPU común

`lie_instance_packet_cache.gd` prepara el ABI existente de instancias/jobs y
acepta una identidad explícita de ensamblaje inmutable. El adaptador WALL15
la liga al banco SHA-bloqueado. Otros adaptadores permanecen dinámicos salvo
que declaren su identidad; no se infieren claves desde campos de UI. LOD y
presupuesto tienen invalidación propia. Se reutiliza la BoxShape3D cuando su
tamaño permanece igual. El consumidor reutiliza conversiones de paquetes
SOLO si sus bytes de entrada y trabajo son idénticos; comprueba parámetros y
resolución en todas las llamadas y valida las entradas nuevas íntegramente.

`lie_light_world.gd` permite agrupar cambios anidados y publica únicamente el
conjunto final validado. WALL13 utiliza ese contrato para posición/orientación/
potencia y prepara la firma desde luces/descriptores pequeños. El modelo de
872 parches solo se necesita en la configuración completa; no se duplica para
comprobar una firma igual ni para un cambio de luz ya residente. Las colas
entre hilos conservan bytes propios, nunca referencias a nodos de escena.
El modo comparativo desactiva lote/cachés de preparación y conserva la ruta
profunda anterior. El validador público de comandos sigue siendo único.

El informe añade CPU por revisión para `instance_packets`,
`effect_configuration` y `light_preparation`, aparte del comando completo.
Son subconjuntos del tiempo total, no tiempos para volver a sumar al comando.
Los contadores de construcción/reutilización permiten verificar el mecanismo.

El informe copiable 1.2 prioriza los tres grupos del diagnóstico y sus comandos
CPU, con resúmenes de etapas y contadores. El historial de timestamps/frames
permanece en `lie-performance-last.json`; no se duplica delante del resumen.
Una prueba con 1,000 filas comprueba que la copia omite ese historial y queda
por debajo de 16 KiB. La selección y el fallback de portapapeles 1.1 continúan.

## Cola GPU de ganadores

Después de rasterizar, una etapa recorre los píxeles y deduplica sus ganadores
reales por índice de proyección. La cola tiene capacidad MAX_WORK y ocupa
16 + MAX_WORK*4 bytes; cada proyección puede añadirse como máximo una vez.
Su encabezado contiene argumentos de dispatch y cantidad; el búfer tiene el
uso oficial STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT. El renderer despacha la
visibilidad desde esa cantidad GPU, sin leer contador ni imágenes en CPU.

La cola persiste durante cambios exclusivos de luz. No altera muestras,
profundidad, acumuladores de material, selección de recuperación, IDs ni
oclusores fuera de cámara. La recuperación solo referencia ganadores reales
de píxeles vecinos. Los resultados se escriben en el índice de proyección
original para que el sombreado siga consumiendo el mismo ABI. La caché por
fuente/luz mantiene sus reglas y conservadora invalidación por posición.

Se conserva una comparación sin compacción. La versión anterior marcaba
candidatos empatados en profundidad incluso si atomicMin elegía otra muestra;
la cola evita esas consultas y omite invocaciones sin ganador. La compacción
añade trabajo al cambiar cámara, que debe incluirse en el coste total, y un
búfer adicional; no se declara una mejora universal hasta medirla.

## Intersección de cajas

Se precalcula el recíproco de cada rayo por sistema de coordenadas, en vez de
dividir por dirección en cada nodo. El nuevo broad phase amplía los intervalos
por redondeo y trata explícitamente ejes paralelos y valores no finitos; ante
un intervalo no finito conserva la prueba anterior. Los discos capturados,
orden de recorrido, distancia cercana y cuantización no cambian. Se prueba
contra el kernel anterior y oráculos float64, y se conserva interruptor.
No es una nueva aproximación de sombra ni reduce el alcance de contacto.

Referencias primarias:
- https://pbr-book.org/4ed/Shapes/Basic_Shape_Interface (recíprocos y tolerancia).
- https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html
  (dispatch indirecto, uso del buffer y sincronización). Se inspecciona además
  la API del binario oficial 4.7.2 que compila este runtime.

## Aceptación

Pruebas independientes: 30,000 cajas/rayos de broad phase, fixtures reales de
visibilidad con ocho canales y referencias float64, packet ABI/LOD/presupuesto,
lotes de emisores, transacciones inválidas y controles. Vulkan compara WALL14
con los modos OFF y ON, vistas 12/60/80°, fuentes puntuales y ocho canales de
área, cero energía, caché de potencia, resize, diagnóstico y memoria/RIDs.
Benchmark intercalado por modo conserva seriales GPU y comandos CPU. No se
presentan tiempos de llvmpipe como mediciones del Mali ni se reduce resolución.

Negativo local conservado: la primera prueba de comandos 1.2 accedía a
request["values"] durante `diagnostic_report`, una petición sin ese campo.
El validador usa ahora el Dictionary vacío obtenido por get; la ruta y prueba
se repiten. No se atribuye a Android/GPU ni se oculta detrás de un timeout.

## Comparación en el teléfono

Abrir 1.2 con los mismos 1080 internos y dos fuentes puntuales de la medición
1.1. Pulsar «Medir modo actual», esperar el fin y copiar el informe. El ensayo
restaura cámara, luces y los tres interruptores de eficiencia. Para aislar un
mecanismo, repetir cambiando solo uno: preparación CPU, superficies visibles o
recorrido de sombras. La posición de luz es el caso prioritario por el coste
de visibilidad recibido. Los contadores de visibilidad siguen apagados por
defecto; encenderlos añade instrumentación y cambia el contexto de la prueba.

Comparar las sumas GPU de cada clase de evento y los comandos CPU por
separado. El FPS de pantalla incluye imágenes guardadas en caché. Tres eventos
sirven para detectar tendencias y validar la ruta; no establecen rendimiento
sostenido ni eliminan diferencias térmicas entre ejecuciones.
