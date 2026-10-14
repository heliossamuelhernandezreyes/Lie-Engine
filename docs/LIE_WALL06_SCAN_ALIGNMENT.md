# WALL06: orientación rígida del escaneo

Continuación de WALL05 para corregir la inclinación repetida de la cara del
maestro. PCA de 23,102 puntos frontales determina una normal
(-0.08287726, 0.31272321, 0.94622173). Una base ortonormal lleva esa normal
a +Z: rotación de 18.8759 grados más centrado del AABB. No se aplana ni
cizalla el escaneo. Distancias entre puntos, colores, radios y atributos
materiales conservados; coordenadas, normales y soportes cambian con SHA nuevo.
La fuente WALL05 permanece bloqueada sin cambios.

El maestro orientado mide aproximadamente 199.47 × 57.55 × 100.63 mm. La
pared recompone el aparejo de 12×8, semilla 2102 y variación de yaw ±0.95°.
Sigue usando un maestro por ID, 96 instancias, un mortero fotografiado y una
sola envolvente física invisible. No se dibuja la malla fuente.

Se transfieren las posiciones del mortero al nuevo paso de las juntas.
Se conserva su RGB/PBR original y el retranqueo medido respecto a vecinos
densos del escaneo antes/después (ocho vecinos, percentil 80, mínimo 0.8 mm).
El cambio del paso altera la distribución espacial del mortero; las máscaras
G1 y altura física absoluta siguen sin certificación. No hay imagen generada
ni relleno de color inventado. El ancho visible heredado es una expansión XY
aproximada del compositor; no equivale a geometría de triángulos exacta.

Los 872 nodos y sus materiales se recalculan de los registros orientados.
El CSR indirecto se vuelve a construir; incluye recorte de oclusores con el
plano frontal, excluye padres de los extremos y conserva normalización
recíproca. No se reutiliza la visibilidad de una geometría distinta. El puente
óptico opaco y las cachés siguen siendo los de WALL05; no se añadieron caminos
refractados ni una BSDF GGX completa. El radio continúa como umbral de calidad
sin cota física general de error para lóbulos direccionales.

Fundamento: [Godot Basis](https://docs.godotengine.org/en/4.7/classes/class_basis.html)
y [PBRT Surface Reflection](https://pbr-book.org/4ed/Radiometry%2C_Spectra%2C_and_Color/Surface_Reflection).
Una base ortonormal conserva la forma; la normalización del transporte se
comprueba por separado de su fidelidad visual.

## Validación y construcción

Pruebas Python: cuatro invariantes nuevos (rigidez, bytes de color/material,
fuente intacta, reciprocidad/pasividad); cuatro regresiones WALL05 y once
pruebas LIE35. Vulkan Mobile compara WALL05 con el nuevo resultado, verifica
cachés frente a reconstrucción, la referencia float64, radio y cambio 2×.
No hay FPS del nuevo APK medidos en el Poco todavía.

APK previsto: LIE Pared 0.3, `org.lieengine.wallruntime.v030`, ARM64 offline,
Godot 4.7.2 y firma debug, instalado junto a versiones anteriores. Banco
precompuesto WALL04 y banco duplicado WALL05 excluidos del APK. El resultado
nativo, hashes y limitaciones se registrarán al completar la construcción.

```sh
python -m unittest discover -s tests -p 'test_lie_wall06*.py' -v
python tools/lie_wall06_android_build.py --stage /tmp/lie-wall06
```

## Resultados negativos

El primer arranque de pruebas de agente sin importar recursos imprimió
`PASS 25` junto con errores de carga de GLSL. Ese resultado no se acepta:
hay que importar shaders y repetir sin errores. Una copia inicial del
constructor tenía imports WALL06 inexistentes por renombrado; se corrigieron
a los módulos compartidos WALL05 antes de publicar/compilar el APK.

La primera construcción `2cffe0a` pasó 24 comprobaciones y generó APK firmado.
Se comprobó después que la etiqueta diagnóstica de transporte aún decía
"original WALL04 CSR" aunque los datos eran el CSR nuevo; se corrige antes
de la entrega final. Se añade una aceptación normalizada por píxeles opacos
con los mismos modos ópticos, luz, cámara y 2×. La primera medida absoluta
(6143 → 1387) mezclaba modos ópticos; no se usa para una afirmación comparativa.
Las imágenes de modo óptico igual sí mostraron mejora (7.48% → 1.80% a 8 bits).
La cifra final se medirá de nuevo directamente en float32.

## Límites de la transferencia

Las normales fotográficas del mortero se corrigen por el cambio de paso XY;
no se recalculan a partir de la derivada del campo de profundidad trasladado.
Por ello no se certifica congruencia completa entre microrrelieve y normales
tras la transferencia. La sombra usa volúmenes recortados por un plano, no
la silueta exacta del escaneo. Los pequeños huecos de cobertura y la iluminación
constante por nodo siguen visibles; esta corrección no certifica G1 o Cycles.

Los tiempos nativos son del compositor en llvmpipe. La captura de control
calentó WALL05 a 1080 antes de cambiar a 2×, mientras las operaciones de luz
WALL06 se midieron a 1440: esos tiempos no son una comparación justa de
rendimiento entre versiones. La aceptación de esta versión es de orientación,
visibilidad y reutilización de cachés; FPS/temperatura del Poco quedan por medir.

## Resultado final

El código `4fcace6` pasó **26 comprobaciones Vulkan Mobile** en
[run 38654258516](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38654258516).
Los 19 workflows de PR finalizaron aprobados. La prueba mantiene óptica,
cámara, luz y resolución 2× iguales antes/después y normaliza por píxeles
opacos: **6143/83160 (7.387%) → 1396/77863 (1.793%)**, reducción aproximada
del **75.7%** en fracción negra. No es una eliminación total de huecos.

Caché frente a reconstrucción: IoU 1, error máximo RGB **1.19e-7**.
Transporte de los 872 nodos frente a float64: **9.89e-9** máximo.
Asignación RD equilibrada: **228,564,244 bytes**, no PSS del proceso.
Banco **41,700,560** bytes + referencias **3,088,388**; una sola subida.
El SHA del banco coincide en entorno local, Vulkan y el APK.

APK entregable **LIE-Pared-0.3.0.apk**, **52,939,190 bytes**, paquete
`org.lieengine.wallruntime.v030`, versión `0.3.0-aligned-optical`, ARM64 offline.
SHA256: `72f8615ecccb85232b038a6fc51e301708a67404533472e373fcad338adc4fb0`.
Firma v2/v3, alineación 16 KiB y manifiesto verificados. Se instala junto a
las versiones anteriores; 2× empieza apagado. El código fuente y los hashes
se preservan en `docs/checkpoints/LIE_WALL06_ANDROID_CHECKPOINT.json`.

El disparo push duplicado fue cancelado por concurrencia antes de ejecutar
pasos; el run de PR citado es el resultado válido. No hubo errores ni fugas
en importación o Vulkan del run final. No se cambió el núcleo de Godot.
