# LIE 2.2: acceso a datos y diagnóstico causal

## Respuesta a la pregunta arquitectónica

LIE no busca una fotografía que coincida con la cámara. La muestra se encuentra
por una referencia estable: `sample_refs[reference_index]` proporciona `sid` y
`samples[sid]` proporciona posición, radio, normal, color y material. Son datos
residentes de GPU, no accesos a archivos, red o una base de datos por píxel.
Compartir el banco evita duplicarlo por ladrillo; no elimina la proyección y
las contribuciones de cada instancia a la pantalla.

Hay otras búsquedas distintas del acceso a esa muestra:

1. Seleccionar bloques de superficie que pueden contribuir a esta cámara.
2. Proyectar sus muestras y recorrer dos veces sus huellas: profundidad y material.
3. Resolver la propiedad del píxel y combinar las contribuciones aceptadas.
4. Filtrar material y buscar vecinos para recuperar huecos.
5. Resolver iluminación local y consultar qué bloquea cada luz activa.

La luz se entrega como **datos**, consumidos por shaders GLSL compilados. Los
emisores publican posición, potencia RGB y radio; el transporte produce un
campo compartido de irradiancia y términos por luz. `injected_*` y «códigos de
luz» nombran paquetes y recursos GPU; no significan generar/incrustar código
de programa nuevo al iluminar cada píxel.

La base interpola hasta nueve nodos de irradiancia por propietario. El
refinamiento puede evaluar hasta nueve nodos por luz activa y una respuesta
local adicional. Con dos luces: hasta 18 evaluaciones de nodo y dos locales
**dentro de ese refinamiento**, además de pesos, material/BRDF, base y sombras.
No son 20 transacciones físicas de memoria ni el total de operaciones de un
píxel. Hay salidas tempranas, huecos, grupos de un solo nodo y cachés.

Las sombras finas consultan primero la visibilidad persistente. Un indicio de
oclusión solo vale después de volver a probar su disco original. Cuando hace
falta, el shader recorre TLAS/BLAS y prueba discos; el coste varía por receptor,
luz e historial. Cambiar únicamente potencia puede aprovechar la respuesta
directa guardada y evitar ese recorrido. Mover la luz invalida su visibilidad.
Una cámara inmóvil sin cambios reutiliza la imagen completa.

Los doce «eventos» del informe 2.1 son doce cambios medidos por grupo; no
cuentan búsquedas. Ese informe no contiene el censo de consultas actual.

## Batería implementada

La escena `lie_renderer_audit_lab.tscn` conserva `command()` y
`compare_kernels`. **Comparar GPU** ejecuta siete casos a la misma resolución
interna, salida, cámara base, banco y secuencia de luces. Cuatro rondas con
orden rotado, tres cambios de cámara, tres de potencia y tres de posición por
caso: 252 eventos medidos. El modo rápido usa una ronda: 63 eventos. Cada caso
conserva además una preparación fría y nueve eventos de calentamiento: 280 o
70, respectivamente. La clasificación se fija antes de ejecutar.

| Caso | Trabajo GPU conservado | Uso del resultado |
| --- | --- | --- |
| Salida residente | Solo resolve/salida de la imagen interna ya residente | Suelo del último paso del consumidor; no es el coste total de Godot |
| Superficie y luz base | Selección, profundidad, material, compactación, filtro y base de irradiancia | Coste del rasterizador actual más su composición base |
| Más recuperación | Añade recuperación original y su reutilización | Coste de reconstrucción de cobertura |
| Más luz detallada | Añade respuesta local de material; contactos finos desactivados y sin grupo de consultas geométricas finas | Aísla ese refinamiento, conservando oclusión/transporte gruesos |
| Más visibilidad fina | Añade claves, invalidación y visibilidad original de discos | Intervalo completo sin respuesta escalar de potencia |
| Completo por etapas | Mismo trabajo anterior con timestamps por etapa | Atribución actual; permite observar el efecto de instrumentar tiempos |
| Producción actual | Activa la caché existente de respuesta a potencia | Compara con el comportamiento actual de la aplicación |

Las imágenes parciales no tienen calidad equivalente al caso completo y no
se presentan como optimizaciones aceptadas. Todos los casos conservan el
transporte grueso/indirecto original, que tiene su propio informe. La suma de
etapas o una diferencia de medianas no sustituye al intervalo GPU exterior.
Los contadores de caché heredados cuentan decisiones del host; la lista de
despachos de cada evento establece qué kernels sí se ejecutaron en una ablación.

La referencia de pared convencional equivalente y un visor Vulkan independiente
**no están implementados** en esta batería. El informe declara esas ausencias;
no usa el viewport con imagen residente como sustituto de una pared convencional,
ni afirma una aceleración por abandonar Godot.

## Censo independiente

Después de los tiempos se ejecutan copias instrumentadas de los kernels
originales 2, 3, 4, 10 y 11. El generador solo añade contadores; no reescribe
sus ecuaciones. Se conservan el banco, discos, límites tangentes y política de
visibilidad del caso completo. Hay una captura fría y los mismos nueve cambios.
Las lecturas GPU explícitas ocurren después, fuera de la batería de tiempos.

Se cuentan invocaciones seleccionadas, huellas activas, candidatos de ambas
pasadas, contribuciones aceptadas de material, evaluaciones de nodos de base,
píxeles refinados, nodos de sus grupos, evaluaciones de nodo/luz y locales,
pares fuente/luz, aciertos de caché/indicio, recorridos completos, nodos de
escena/BLAS y pruebas de disco. También se leen ganadores únicos, bloques
seleccionados y registros/desbordamientos de recuperación existentes. Estos
últimos describen la geometría residente en cambios de luz.

Son conteos lógicos uint32, no transacciones DRAM, rayos de hardware o
instrucciones. No se instrumentan lecturas de vecinos de recuperación. Una
cifra que exceda uint32 puede desbordarse; no se certifican cargas arbitrarias.
Los tiempos de los shaders instrumentados se excluyen de los resúmenes de FPS.

El informe copiable incluye todos los resúmenes y el censo. El archivo
`user://lie-renderer-audit-last.json` conserva eventos, seriales, despachos,
tiempos por etapa, calentamiento y límites de telemetría completos. Cancelar
restaura el estado previo y fuerza una reconstrucción completa original.

## Corrección de dominio de borrado

El clear ahora cubre `max(referencias, píxeles, 512²)`. La prueba Vulkan ensucia
los flags de todas las 535.670 referencias y comprueba que no quede ninguna
tras borrarlas a 1080→720→720. También compara cambios de luz después de cada
paso con visibilidad recomputada desde cero. La regresión antigua dejaba
17.270 referencias sin visitar a 720. Es una corrección de cobertura; no se
atribuye a ella la demora de 34 ms.

## Validación

```
python -m unittest discover -s tests -p test_lie_renderer_audit.py -v
python tools/lie_renderer_census.py
python tools/lie_hardware_build.py --cache /tmp/lie-probe --platform linux.x86_64
python tools/lie_renderer_audit_build.py --stage /tmp/lie-renderer-audit
```

Con Godot 4.7.2 se importan los recursos y ejecutan los comandos, el rig CPU,
el agente y `test_lie_renderer_audit_gpu.gd` en Vulkan real con el banco atribuido.
La prueba comprueba imagen de producción, paridad de imagen/material de los
kernels instrumentados, conteos no vacíos y coherentes, borrado del dominio,
despachos de las ablaciones, todos los tiempos exteriores, restauración e
informe copiable. El workflow construye además el módulo ARM64 y APK firmado.
Software Vulkan comprueba ejecución/corrección; no mide rendimiento del Mali.
