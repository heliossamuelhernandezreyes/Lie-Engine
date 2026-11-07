# LIE Benchmark 6.0.1 · medición y copia automática

Entrega aceptada: [GitHub Actions 42394015221](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42394015221), código de la APK `9d7a5b6ee435bf76fe17774c7820c123e80f0eae`. Todas las etapas aprobaron. APK de 216 770 741 bytes, SHA-256 `1ea56c258ced80bb5d3161fc10a344580312406dba3468d954cacfe9dfd67639`. Se verificaron los 90 archivos de datos, firma, alineación, registro nativo y permisos.

Validación: 284 pruebas Python aprobadas y una omitida; 103 comprobaciones Vulkan (49 de construcción, 26 del campo y 28 móviles); seis de métricas, 16 de la extensión nativa, 247 del rig y 25 del agente. El registro reproducible está en `docs/checkpoints/LIE_CONSTRUCTION_ANDROID_V601.json`.

El laboratorio coloca **Benchmark y copiar informe** en una barra fija encima de la imagen. Ejecuta la comparación ya validada: 24 eventos de cámara y 24 de movimiento de luz en cada uno de los dos modos, directa sin rebotes y directa con dos rebotes. Conserva la resolución y los demás ajustes seleccionados, los restaura al terminar y copia el resumen JSON al portapapeles.

Al finalizar aparece **Informe copiado. Vuelve a ChatGPT y pégalo.** No es necesario desplazarse por el panel ni abrir el diálogo del informe. La misma copia automática se aplica a las sesiones completas de 60 segundos y diez minutos. Se conserva la exportación del JSON completo mediante el selector de Android.

La barra incluye **Copiar informe** para repetir una copia y **Detener** para cancelar. La copia automática sólo ocurre si la prueba termina sin error y sus ajustes se restauran. Una cancelación, un error o una interrupción por pérdida de foco conservan lo que ya estaba en el portapapeles. La copia manual permite enviar también un informe parcial, marcado como incompleto o cancelado.

El botón principal permanece deshabilitado mientras se prepara el consumidor gráfico o se ejecuta una prueba. Los controles de escena se bloquean durante la medición. Si el sistema no proporciona portapapeles, el estado muestra que el informe está listo y mantiene disponible el diálogo para seleccionar el texto, sin afirmar que se copió.

Esta entrega se instala como **LIE Benchmark 6.0.1**, paquete `org.lieengine.construction.v601`, código 601, versión `6.0.1-auto-benchmark`. Usa un identificador distinto para poder instalarla junto al experimento v6 anterior: su clave temporal de depuración no permite una actualización firmada sobre aquella APK. No se elimina la aplicación anterior ni sus informes. Para futuras actualizaciones estables hará falta conservar una clave de firma privada; no se publica ninguna clave privada en el repositorio.

No cambia la reconstrucción, los shaders, la iluminación, los datos ni la selección de LOD. Se conservan los 90 archivos SHA-verificados del banco aceptado y las resoluciones explícitas 960/1920, 720/1440 y 480/960. Los bytes de recursos contabilizados no equivalen a RAM total del proceso. Los FPS de una escena quieta no demuestran rendimiento en movimiento; el benchmark conserva tiempos de pantalla, CPU, apariencia GPU, campo y telemetría por separado.

La prueba nativa del laboratorio comprende 28 comprobaciones. Añade validación de que la acción está encima de la imagen, el portapapeles contiene el informe completo de la medición actual, existe confirmación visible, una cancelación conserva el contenido anterior y el botón de copia permite copiar explícitamente un resultado cancelado. Se conserva la verificación de gestos, estados atómicos, cambios de resolución, campo, restauración y ausencia de readbacks GPU durante las mediciones. Las pruebas del portapapeles se ejecutan en un servidor gráfico desechable, sin acceder al de una sesión de usuario.

Compilación y pruebas: `.github/workflows/lie-construction-android.yml`. El informe de la entrega anterior y los detalles de instrumentación siguen en `LIE_CONSTRUCTION_ANDROID_V6.md`. La copia mediante el portapapeles de Android debe confirmarse en el teléfono; la prueba nativa de escritorio y la verificación del APK no la sustituyen.
