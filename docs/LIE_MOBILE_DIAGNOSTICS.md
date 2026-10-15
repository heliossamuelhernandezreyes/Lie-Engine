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

Local, Godot oficial 4.7.2: reductor 8 comprobaciones, controles 15,
regresiones Python de área/filtro 7. Vulkan y portapapeles con display real
se verifican por el workflow dedicado antes de aceptar la APK. Las pruebas
incluyen imagen idéntica a WALL13, nueve cambios reales, restauración visual,
portapapeles, una sola subida y una caja invisible. El informe no afirma
haber ejecutado Android físico: el resultado del Poco debe salir del APK.

Se conservan fallos de infraestructura local: apt inicial no pudo cambiar
UID del usuario de descarga; se intentó instalación sin ese cambio de UID.
No se presenta ese fallo como defecto gráfico de LIE. El proyecto aislado
importa y ejecuta las comprobaciones CPU sin sustituir Vulkan por mocks.
