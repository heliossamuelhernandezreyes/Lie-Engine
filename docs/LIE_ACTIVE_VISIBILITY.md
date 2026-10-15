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
