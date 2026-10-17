# LIE 2.0: respuesta directa y envío a GPU

Al variar solamente la potencia, el consumidor volvía a calcular el relieve,
la BRDF y la visibilidad directa por píxel. Ahora captura el término directo
anterior y su reemplazo detallado por píxel y luz física durante el primer
cambio compatible. Los cambios posteriores escalan ambos términos. El campo
indirecto, su transporte y la composición base se vuelven a resolver mediante
las ecuaciones anteriores; no se supone que ese campo sea lineal.

El primer cambio de potencia conserva el coste de construcción. Cámara,
posición de luz, materiales, resolución y opciones invalidan la respuesta.
Los paquetes residentes deben conservar posición, radio y forma cromática;
los valores no finitos, negativos y próximos al umbral cero se rechazan.
La ruta rápida tiene cuatro descriptores y ninguna consulta geométrica.

La caché se asigna bajo demanda: 128 + tamaño² × luces físicas × 32 bytes.
A 1080 son 74.649.728 bytes para dos luces y 298.598.528 para ocho muestras de
área. Son bytes solicitados, no una medición de VRAM o PSS. No se modifica el
banco fotográfico ni se añaden mallas visibles de la fuente.

Cada modo conserva un intervalo GPU exterior idéntico para la apariencia.
Los tiempos por etapa se guardan aparte y nunca se suman a ese intervalo.
El transporte permanece separado. Cuatro rondas rotadas conservan 144 eventos
medidos y 160 de calentamiento, incluidos construcciones frías y picos.
Los FPS de pantalla incluyen imágenes en caché y no sustituyen esta medición.

Valores predeterminados: respuesta activada, medición por etapa desactivada,
límites ajustados activados, bloques de pantalla desactivados y envío ligero
desactivado. Este último evita restaurar estados que el siguiente despacho
vuelve a establecer, pero las pruebas no demostraron una mejora consistente.

## Resultados anteriores a la recuperación

La ejecución anterior con llvmpipe LLVM 20.1.2 produjo estos p50 en ms, con
12 eventos por grupo. Esta tabla transcribe el registro de la sesión: el
archivo original de eventos se perdió con la copia temporal y **no se ha
reconstruido como si fuera evidencia bruta**.

| Cambio | Referencia | Respuesta | Medición global (predeterminado) | Envío ligero |
|---|---:|---:|---:|---:|
| Cámara | 241.122037 | 239.495924 | 243.573291 | 245.644723 |
| Potencia | 90.583843 | 44.464693 | 45.119103 | 45.514220 |
| Posición de luz | 134.064390 | 127.029244 | 115.775039 | 134.607641 |

En esa ejecución pasaron 101 comprobaciones del consumidor, incluyendo HDR,
profundidad, apagado/encendido, invalidación y restauración. El máximo error
HDR escalado de los cinco pares fue 8,4134e-7 y la intersección de siluetas
fue 1. La cámara no obtuvo una mejora importante. Ninguna cifra anterior
certifica FPS en el Poco: el resultado físico 2.0 sigue pendiente.

Se conservan también los negativos: el primer candidato guardaba solamente
el término detallado y redujo potencia de 92,40 a 72,06 ms; el envío ligero de
ese candidato llegó a 1.285,26 ms en cámara. Un exportado intermedio contenía
una extensión nativa vacía: fue rechazado y nunca se entregó. El exportador
ahora comprueba existencia, ELF64 ARM64 y hash antes de exportar, y rechaza
errores de Godot aunque el proceso termine con código cero.

## Correspondencia con el APK entregado

`LIE_POWER_RESPONSE_RECOVERY.json` registra la recuperación desde el APK
2.0.0 ya entregado. Los diez scripts nuevos/modificados coinciden al
descompilar y volver a compilar; los dos shaders producen SPIR-V idéntico
byte por byte con Godot 4.7.2. Los comentarios y formato originales no son
recuperables. El historial local que no llegó a GitHub tampoco se conserva.

Las herramientas Python, pruebas y documentación de esta rama se han
reconstruido por separado. Sus nuevas ejecuciones y los artefactos de CI son
evidencia nueva, distinta de la tabla histórica anterior.

Para reproducir: ejecutar los tests Python `test_lie_power_response.py` y
`test_lie_android_extension_inputs.py`, generar con `lie_wall23_shader.py`,
preparar el proyecto con `lie_wall23_android_build.py` y usar Godot 4.7.2 para
`test_lie_wall23_commands.gd`, `test_lie_light_field_gpu.gd` y
`test_lie_wall23_mobile.gd`. Este último usa Vulkan real y el banco verificado;
`LIE_RESPONSE_QUICK=1` reduce solamente la matriz a una ronda. No elimina
comprobaciones visuales ni picos. La compilación de Android y las regresiones
anteriores continúan en `.github/workflows/lie-gpu-diagnostics.yml`.

## Nueva ejecución tras recuperar las fuentes

La nueva ejecución pasó 118 comprobaciones Vulkan del consumidor, 374 del
campo (15 escenarios), 33 de comandos, 19 de comandos de bloques y 18 tests
Python. Conservó 144 eventos medidos y 160 de calentamiento. Se recalcularon
independientemente los p50/p95 CPU y GPU de los doce grupos y coincidieron.
Los JSON `LIE_POWER_RESPONSE_RECOVERED_NATIVE.json` y
`LIE_POWER_RESPONSE_RECOVERED_FIELD.json` contienen la evidencia nueva completa.

| Cambio | Referencia | Respuesta | Medición global | Envío ligero |
|---|---:|---:|---:|---:|
| Cámara (p50 ms) | 210.133508 | 220.185896 | 215.357384 | 208.474629 |
| Potencia (p50 ms) | 71.538764 | 40.255919 | 65.155666 | 40.311567 |
| Posición (p50 ms) | 109.915602 | 113.715884 | 105.492023 | 112.155500 |

Esta repetición confirma la corrección visual y una respuesta reutilizada
más barata, pero muestra variación considerable de tiempo: el modo global
solo redujo el p50 de potencia un 8,9% aquí, frente a la reducción cercana al
50% de la ejecución histórica. Se conservaron todos los picos. No justifica
extrapolar una ganancia fija, modificar los valores predeterminados a partir
de un solo ensayo o predecir FPS del teléfono. Cámara sigue sin un salto de
rendimiento. El máximo error HDR escalado de los pares fue 8,4134e-7.
