# LIE 1.1 — medición y controles táctiles

Base: 32ef4722173a170deced835e411dfd02a8040548, WALL13 / APK 1.0.
Solicitud: localizar el cuello de botella en el teléfono, corregir el informe
que no se puede copiar y manipular la vista de la pared directamente.

## Informe

WALL14 permite abrir un informe sin ejecutar antes la prueba de cuatro modos.
El texto es visible, seleccionable y de solo lectura. Copiar comprueba el
roundtrip del portapapeles después de 200 ms e informa éxito o selección
manual disponible. No se declara copia exitosa sin leer el mismo contenido.
El JSON completo se guarda en `user://lie-performance-last.json`; los errores
de guardado se muestran. La transferencia al portapapeles omite historiales
CPU y copias redundantes de filas GPU, y conserva un resumen, configuración,
seriales y 32 filas recientes. Esto reduce el tamaño del IPC Android. No se
atribuye el fallo reportado a un límite concreto sin logs del teléfono.
No solicita almacenamiento externo ni permisos de red.

## Medición

Se conservan timestamps asíncronos de TODOS los pases de apariencia, incluidos
visibilidad 3D, preparación e invalidación de sombras, filtro y composición
fusionada. El reductor agrupa por resolución, opciones efectivas, cantidad de
canales físicos y tipo de evento. Excluye eventos incompletos; conserva filas
crudas en el informe completo. Ordena etapas por mediana y calcula p95 mediante
rango más cercano. El porcentaje usa la suma de medianas de etapas del mismo
grupo; la mediana total procede de sumar pases por serial antes de reducir.
El tiempo del transporte luminoso permanece separado y conserva sus seriales.

`diagnose` ejecuta nueve cambios con la calidad actual: tres cámaras, tres
potencias y tres posiciones de luz. Bloquea cambios externos, acepta cancelar
y restaura el estado mediante el mismo validador. Los seriales permiten unir
cada cambio con sus timestamps. La latencia del evento acaba cuando se observa
el envío CPU al renderizador; NO significa GPU terminada. La GPU se mide con
timestamps. La prueba de cuatro modos anterior sigue disponible.

El informe incluye tiempo CPU de aplicar controles, monitor de proceso Godot,
intervalos de pantalla, FPS de presentación, bytes solicitados por recursos,
memoria estática Godot y tiempos de viewport publicados por el backend.
Ninguno de esos contadores equivale a PSS Android, VRAM física o temperatura.
Un pase GPU dominante no demuestra por sí solo un cuello de botella global;
CPU, sincronización, transporte y trabajo del motor requieren sus métricas.
Sin timestamps válidos se informa ausencia, nunca un coste inventado de cero.

## Gestos

Un dedo orbita la cámara, dos dedos ajustan su distancia. Arrastrar con ratón
y rueda ofrece el equivalente de escritorio. El gesto debe empezar sobre la
imagen; el panel mantiene sus controles. Se ignora el ratón sintetizado desde
el toque, se limpia al perder foco y se bloquea durante medición/informe.
Los movimientos se acumulan y producen como máximo una transacción validada
por cuadro; actualizan también los deslizadores. Se inspecciona el objeto:
NO se traslada físicamente la pared ni se altera el banco, las luces o el
collider. La interfaz lo describe como «girar la vista».

## Verificación y límites

Local, Godot oficial 4.7.2: reductor 9 comprobaciones, controles 19,
regresiones Python de área/filtro 7; rig 247 y agente 25 tras importación. Vulkan y portapapeles con display real
se verifican por el workflow dedicado antes de aceptar la APK. Las pruebas
incluyen imagen idéntica a WALL13, nueve cambios reales, restauración visual,
portapapeles, una sola subida y una caja invisible. El informe no afirma
haber ejecutado Android físico: el resultado del Poco debe salir del APK.

Se conservan fallos de infraestructura local: apt inicial no pudo cambiar
UID del usuario de descarga; se intentó instalación sin ese cambio de UID.
No se presenta ese fallo como defecto gráfico de LIE. El proyecto aislado
importa y ejecuta las comprobaciones CPU sin sustituir Vulkan por mocks.


## Primera ejecución nativa conservada

Código 622851b49f6058dd8fdbb6b32225899ba76fa44e, run 38758447231:
WALL14 aprobó 12 comprobaciones Vulkan, incluido portapapeles y nueve eventos.
WALL13 aprobó 50. El job se detuvo posteriormente en WALL09: su contrato
exacto de contexto no incluía la nueva clave `event_kind`. La muestra real
contiene `geometry`, coherente con reducir 1440 a 1080 en esa comprobación.
Se amplía la igualdad esperada con esa clave; no se relajan tolerancias de
imagen ni tiempos. No se exportó APK de ese run. Evidencia WALL14 completa:
`checkpoints/LIE_DIAGNOSTICS_FIRST_NATIVE.json`; artefacto 11983944729,
3,027,091 bytes, SHA256 445f687f4d9c0698e5548ffb1d213bdc209cfe7de88233096701ad7d27a68681.

La revisión de límites detectó un ensayo de potencia que podía quedar sin
cambio al recortar al mínimo/máximo. Se usan tres potencias distintas dentro
del intervalo y se verifica .25/1/3. La reducción añade etiquetas por serial
para separar potencia y posición de fuente, incluso compartiendo el mismo
contexto de luz. Una prueba de despacho de entrada necesitaba esperar también
el evento de liberación; con esa espera pasa la ruta real de Input y no deja
un dedo activo. No se modifica el control para satisfacer ese desfase del test.

El primer intento del agente local se lanzó antes de terminar la importación
de GLSL y registró dependencias sin loader, aunque imprimió 25 checks; ese
intento no se acepta. Tras importar, las mismas 25 comprobaciones pasan sin
errores. La instalación Vulkan local también encontró archivos de apt de
solo lectura; la verificación gráfica se ejecuta en el runner nativo.
