# LIE 6.4.0: selección nativa y proyecciones sin pérdida

Esta versión incorpora una parte del núcleo de LIE en C++17 y conserva Godot
como anfitrión. La reconstrucción continúa en la GPU. Mantiene las capturas,
los LOD solicitados, los identificadores originales y la resolución predeterminada
de salida 960 / interna 1920. No constituye todavía un renderer por tiles ni
un sistema general de oclusión.

## Uso en el teléfono

1. Instala `LIE-Construccion-v6.4.0.apk` y abre **LIE Benchmark 6.4.0**.
2. Pulsa **Probar núcleo y copiar**. Compara la selección nativa apagada y
   encendida con el mismo recorrido, en orden A/B/B/A, en conjunto y de cerca.
3. Espera a que termine. Los ajustes se restauran y el informe se copia
   automáticamente. Pégalo en el chat para evaluar este teléfono.

El interruptor **Descartar caras de espaldas** permite comparar visualmente.
**Probar jerarquía y copiar** mide por separado la selección por encuadre.
**Benchmark y copiar informe** conserva la comparación de iluminación directa
y dos rebotes. Una imagen reutilizada no cuenta como nueva reconstrucción.

## Qué cambió

### Agrupación por índices, con fuente intacta

El primer experimento agrupó 64 muestras consecutivas. Fue conservador, pero
no eliminó ninguna muestra en las tres escenas examinadas: el banco mezcla
caras distintas en su orden de almacenamiento. Ese resultado negativo está
preservado en el checkpoint y en la evidencia.

La solución agrupa índices por orientación de la normal geométrica y posición
local. Se usan etiquetas de 4 × 4 por cara dominante y orden Morton para
construir grupos de hasta 64 muestras. **No se cuantizan las normales que se
dibujan ni se reescriben posiciones, materiales o muestras del banco.**

Cada grupo conserva intervalos que incluyen todas sus posiciones y normales.
El planificador calcula una cota superior del producto entre la normal y el
vector hacia el ojo en espacio local. Solo descarta grupos cuya cota es
estrictamente negativa, con un margen numérico amplio. Los casos inestables
y las deformaciones no admitidas conservan el trabajo.

El planificador C++ valida las particiones y las permutaciones. Reutiliza esa
validación únicamente mientras retenga las mismas instantáneas inmutables.
Genera listas de índices para el binding de trabajos ya existente: no añade
otro descriptor. Los índices de propietario globales permanecen iguales,
incluidos los desempates de profundidad.

Los trabajos completos se conservan para sombras y para los propietarios del
campo de luz. Descartar una muestra de cámara no elimina su objeto del mundo.
Si faltan la extensión compatible o los metadatos verificados, se mantiene
la ruta de cámara sin este descarte.

### Proyecciones de 64 bytes

Se eliminaron cuatro escalares sin consumo útil. El SID de fuente llega de
forma explícita a la comprobación de soporte. Los valores retenidos siguen
siendo float32 y no se reducen ni resolución ni detalle.

| Offset | Campo | Bytes |
|---:|---|---:|
| 0 | Normal de apariencia | 12 |
| 12 | Profundidad de la muestra | 4 |
| 16 | Centro proyectado | 8 |
| 24 | Gradiente de profundidad | 8 |
| 32 | Normal geométrica | 12 |
| 44 | Propietario de instancia | 4 |
| 48 | Elipse | 12 |
| 60 | Radio proyectado acotado | 4 |

Se verificaron los offsets en el SPIR-V compilado. Para la capacidad de
1,179,648 registros de la esquina, el buffer baja de **90 a 72 MiB**.
Las listas de índices consumen memoria adicional; ese ahorro de 18 MiB no
debe confundirse con la reducción total del proceso. El acumulador de píxeles
continúa ocupando 112.5 MiB a interna 1920².

### Límites y calidad explícitos

Se comprueban límites de descriptores, grupos e imagen antes de inicializar.
En Vulkan se consulta `VkPhysicalDeviceProperties` mediante handles prestados
de RenderingDevice. Sin esa consulta se usa la cota conservadora de 128 MiB
para el rango de almacenamiento. No se crean buffers que excedan el límite
conocido. La extensión no posee ni destruye el dispositivo de Godot.

El constructor deja de rebajar automáticamente el LOD al superar el presupuesto
de muestras. Presenta el límite y exige elegir detalle explícito o dividir el
trabajo. Este cambio no implementa todavía streaming de escenas arbitrarias.

## Qué se verificó

El checkpoint final y el paquete de pruebas contienen los resultados completos,
los hashes, los intervalos por pase y la comparación independiente con 6.3.0.
La validación no se sustituye por contar muestras:

- Extensión C++ real cargada y pruebas de partición, entradas inválidas,
  transformaciones reflejadas, escalas y orientaciones.
- Comprobación NumPy independiente de **cada muestra omitida** en tres escenas
  usando los bancos originales.
- Comparación Vulkan de imagen RGBA, profundidad, sombra, propietario y
  acumulación de material, incluyendo puertas, ventanas, vistas cercanas,
  encuadre vacío y orden inverso de bancos.
- Comparación de imágenes con el código 6.3.0 fijado en otro checkout.
- Repetición de los mismos shaders en C++/Vulkan fuera de Godot.
- Compilación ARM64, firma, alineación y verificación independiente del APK.

El benchmark mide CPU nativa y GPU por separado. Su tiempo CPU incluye el
planificador y el empaquetado de sus listas; no representa toda la lógica CPU
de la aplicación. Los tiempos software no son FPS del Poco.

### Resultados de esta compilación

En la esquina a salida 960 / interna 1920, las invocaciones de cámara pasaron
de **1,165,568 a 672,184**: 493,384 menos, **42.33 %**. Se conservaron exactamente
los valores RGBA, la profundidad, las sombras y los hashes completos de
propietario/material. Siete de las nueve vistas de la prueba redujeron trabajo;
las otras dos no tenían muestras de cámara.

El control corto A/B/B/A de Vulkan software usó salida 256 / interna 512 y
dos eventos por bloque. Cada celda siguiente muestra los p50 informados por
los dos bloques de ese modo, sin sumar ni promediar percentiles:

| Vista | Selección apagada, apariencia ms | Selección activa, apariencia ms | CPU nativa activa ms |
|---|---|---|---|
| Conjunto | 818.02 / 868.91 | 494.05 / 496.15 | 2.745 / 2.720 |
| Cerca | 1546.17 / 1499.11 | 893.25 / 876.78 | 1.707 / 1.689 |

Es una mejora observada en ese control de software y un resultado demasiado
corto para certificar rendimiento sostenido. No acredita esas reducciones
temporales en Mali, Adreno o el Poco. La prueba física del botón usa más eventos.

La batería Python tuvo 287 pruebas, con una omitida. Pasaron 57 comprobaciones
Vulkan de la nueva selección, la jerarquía existente (53), reconstrucción (28), materiales HQ
(49), campo (26), móvil (28), física (65), proxies GPU (15), métricas (9),
telemetría (17), rig (247) y sesión de agente (25). La comparación independiente
con 6.3.0 tuvo error RGBA máximo cero en sus diez casos.

El APK verifica 105 archivos de datos/metadatos. **Los 90 archivos originales
de 6.3.0 conservan sus hashes**; los quince añadidos contienen únicamente
metadatos e índices de visibilidad. No se remuestrearon las capturas.

Runtime: `94ac4f1ee225da96155f7e60433f9eaf11408f71`.
CI principal: run `42527505716`; control nativo: run `42527505777`.
SHA-256 del APK:
`e63dbf16b210c2febba927df85f7c32be3678a0b2031ed65e9466dcdaaefaa31`.

## Límites que permanecen

El compilador estático de Arm sigue mostrando derrames de registros. La
compactación no los elimina universalmente: algunos pases y modelos mejoran
y otros empeoran en ese análisis. Se conservan todos los informes. Hacen falta
medidas físicas para saber el balance en cada driver.

La ruta de referencia todavía necesita 12 buffers de almacenamiento y shaders
compatibles con su SPIR-V. Esta entrega ARM64 no certifica todas las GPU ni
aporta un fallback GLES. La selección de caras no descarta automáticamente
una pared frontal tapada por otra: la oclusión conservadora y la rasterización
por tiles siguen pendientes.

Reducir invocaciones no implica reducir en el mismo porcentaje el tiempo de
imagen. Las muestras de espaldas ya se rechazaban dentro del shader; las
huellas visibles, las sumas atómicas y el sombreado aún deben resolverse.
Este núcleo permite organizar ese trabajo y medir su coste real sin perder
la referencia de calidad.
