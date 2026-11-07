# LIE Construcción v6 · laboratorio Android

La aplicación reúne el banco fotográfico v5, la residencia por intervalos exactos de v6 y su campo indirecto común. Es un laboratorio de construcción, iluminación y medición; todavía no es una casa completa. La APK es independiente de las antiguas aplicaciones de pared.

## Entrega aceptada

[Ejecución de GitHub Actions 42391062122](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42391062122), código de la APK `33c4486689f3a2c63d8131656b8e9d2c0eabc640`: todas las etapas aprobadas. APK `LIE-Construccion-v6.apk`, **216 770 741 bytes**, SHA-256 `3fbb3026d2fdab731bfdafb70a945d5f7290422088ad4308fcdc327370e99ac4`.

Se aprobaron 284 pruebas Python y se omitió una, 98 comprobaciones Vulkan del consumidor actual (49 de construcción, 26 del campo y 23 móviles), seis de resumen de métricas, 16 del módulo nativo, 247 del rig y 25 de la sesión de agente. Se verificaron los 90 archivos de datos dentro de la APK, firma, alineación, registro de la extensión, tres bibliotecas ARM64 y atribuciones. El manifiesto no solicita permisos de Internet ni de almacenamiento general.

La esquina completa conserva **336.98 MiB de recursos RenderingDevice contabilizados**: 12 335 104 bytes de capturas residentes, 316 911 568 de apariencia y 24 105 544 del campo. Se conserva la resolución 960/1920 y los 4 742 parches. No son mediciones de memoria total ni de un Android físico. El registro de entrega reproducible está en `docs/checkpoints/LIE_CONSTRUCTION_ANDROID_V6.json`.

## Uso en el teléfono

1. Descargar `LIE-Construccion-v6.apk` e instalarla. Android puede pedir habilitar la instalación desde la aplicación que abre el archivo.
2. Abrir **LIE Construccion 6** y esperar la preparación inicial de shaders, capturas y campo. Usar el teléfono horizontalmente.
3. Arrastrar con un dedo sobre la imagen para girar. Con dos dedos se acerca/aleja y desplaza el encuadre. **Centrar cámara** restaura la vista inicial.
4. Deslizar el panel derecho para ver todos los controles y las mediciones. Elegir esquina, marco, cubierta, puerta o un componente individual. El ángulo de puerta se aplica al conjunto de puerta.

El valor inicial es **salida 960 px / reconstrucción interna 1920 px**, igual que en la validación de escritorio. Las opciones 720/1440 y 480/960 son cambios explícitos de resolución. No alteran las fuentes, las capturas ni los LOD elegidos por la receta. Cambiar de resolución sustituye el consumidor gráfico y conserva el campo de la misma escena. Las fuentes completas 8K siguen conservadas en los paquetes anteriores; la APK necesita sus capturas derivadas, no los archivos fotográficos de autoría.

## Primera medición recomendada

Mantener inicialmente la resolución y los ajustes predeterminados. Pulsar **Comparar directa / 2 rebotes**. La prueba emplea las mismas dos fuentes y las mismas secuencias de cámara y movimiento de luz: compara cero rebotes frente a dos rebotes. Conserva el calentamiento por separado y restaura todos los ajustes al terminar.

Después ejecutar **Sesión de 60 segundos**. Alterna bloques de diez segundos de cámara, luz y escena quieta. Si funciona de forma estable, ejecutar **Sesión de 10 minutos** en condiciones de uso habituales. Esta sesión conserva el modo de iluminación seleccionado y sirve para observar evolución temporal; no cambia automáticamente la calidad para ocultar una caída de rendimiento.

**Detener prueba** cancela la medición y restaura los ajustes. Pasar la aplicación a segundo plano o perder foco también cancela la prueba para no mezclar una interrupción del sistema con una sesión continua. Durante la medición se bloquean los controles que cambiarían sus condiciones. El informe indica si fue completa, cancelada o si encontró un error.

## Iluminación

- **Campo LIE** activa el consumidor con luces registradas y campo superficial. Desmarcarlo abre la referencia anterior, de una sola luz, con residencia optimizada. Esa referencia no es una medición del antiguo consumidor que cargaba todos los bancos completos. Los controles de segunda luz y rebotes se deshabilitan en ella.
- **Mostrar rebotes indirectos** conmuta su contribución en apariencia. Desmarcarlo por sí solo no detiene el cálculo del campo. La comparación automática sí configura cero o dos rebotes para medir ambos casos de forma explícita.
- **Rebotes calculados** selecciona de cero a cuatro generaciones secundarias. Principal y segunda luz pueden retirarse independientemente del campo.
- **Radio energético** activa la política ya existente de área/irradiancia y recorte por generaciones; no sustituye las pruebas de visibilidad. Empieza desactivado.
- **Ambiente** es una contribución común adicional. Bajarlo a cero ayuda a examinar la iluminación producida por las fuentes y sus rebotes.

La visibilidad indirecta usa perfiles conservadores y un grafo truncado, no todas las intersecciones con las mallas fuente. No se incorpora vidrio, refracción, especular indirecta dependiente de vista ni geometría nativa de Godot de forma automática. El microdetalle perdido en v5 sigue siendo una limitación de su representación.

## Leer y compartir el informe

**Informe / copiar** muestra un resumen JSON seleccionable. **Copiar resumen** permite pegarlo en esta conversación. **Guardar JSON completo** utiliza el selector de archivos del sistema para elegir el destino; el informe completo conserva las filas crudas de tiempos GPU. La aplicación guarda además el último informe internamente y lo recupera al abrirse de nuevo. En sesiones largas guarda un resultado parcial después de cada bloque, marcado como incompleto hasta terminar.

| Medida | Significado |
| --- | --- |
| Pantalla FPS | Ritmo observado de los fotogramas de la aplicación; una escena quieta puede reutilizar su imagen |
| `display_frame_ms` | Intervalos entre llamadas de proceso; incluyen CPU, espera y presentación. No son sólo tiempo de shader |
| `command_cpu_ms` | Tiempo de aplicación del comando validado y actualización de escena/UI; no incluye el trabajo GPU posterior |
| `appearance_gpu_ms` | Intervalos de timestamps de reconstrucciones realmente ejecutadas |
| `lighting_gpu_ms` | Intervalos independientes de cálculos del campo; no aparecen nuevos cálculos en una cámara que reutiliza la luz |
| Recursos LIE | Bytes contabilizados en las asignaciones RenderingDevice de apariencia y campo |
| RSS / PSS | Medidas distintas de memoria del proceso obtenidas, cuando es posible, de `/proc/self/status` y `/proc/self/smaps_rollup`; no se suman ni representan memoria exclusiva GPU |
| `thermal_status` | Política térmica global de Android; no es una temperatura de GPU |
| `gpu_temperature` | Sensores legibles cuyo nombre declara explícitamente GPU/Mali. Si no existen o no son legibles se informa como no disponible |

Los percentiles p50 y p95 se calculan por bloque y configuración; no se suman los percentiles de apariencia y luz. Un bloque quieto no inventa un cálculo de LIE de cero milisegundos. Los datos ausentes llevan disponibilidad/motivo y no se convierten en ceros. Los identificadores de productor y las épocas distinguen reemplazos y evitan mezclar seriales de efectos distintos.

La instrumentación también tiene coste: copia metadatos/timestamps asíncronos y consulta telemetría aproximadamente cada medio segundo. En la medición no se leen texturas ni buffers de imagen, no se solicita una sincronización GPU explícita y no se activan contadores privilegiados de Mali. La aplicación no envía los informes automáticamente y no solicita permiso de Internet ni acceso general de lectura/escritura del almacenamiento. El selector de guardado concede acceso al destino que elige la persona.

## Construcción y validación

El workflow `.github/workflows/lie-construction-android.yml` restaura el artefacto v6 aceptado `13572886857`, SHA-256 `2b1ddcb8bdf1aa59482f92418792cefae349797847216b1e2a60c3de498738e0`. Verifica y empaqueta los 90 archivos de capturas/metadatos, sus cinco bancos geométricos y las normales ópticas. No recaptura ni remuestrea los assets.

Reutiliza la exportación Android de Godot 4.7.2, Java 17, build-tools 36.0.0 y NDK 28.2.13676358. La APK usa ARM64, Vulkan/Mobile y el paquete `org.lieengine.construction.v6`, versión `6.0.0-construction-field`. Es una compilación experimental firmada con clave de depuración, no una publicación en una tienda.

El flujo ejecuta las regresiones Python; compila los GDScripts; verifica rig, agente, resumen de métricas y módulo nativo; ejecuta las pruebas reales Vulkan de construcción, campo e interfaz móvil; exporta, normaliza manifiesto, alinea a 16 KiB, firma y verifica la APK. La comprobación independiente inspecciona cada SHA de datos dentro de la APK, escena inicial, bibliotecas ELF ARM64 y alineación, permisos y atribuciones.

La prueba móvil cubre gestos, controles inválidos, imagen directa/indirecta, contabilidad sin readbacks, comparación y restauración, cancelación, cambio de resolución con campo activo y regreso a la esquina de calidad completa. Los ensayos nativos usan Vulkan de software en escritorio: **no constituyen una prueba de FPS, temperatura, consumo total o estabilidad sostenida de un Android físico**. El guardado mediante el selector Android requiere todavía validación en el teléfono.

Los errores de compilación iniciales de un nombre reservado de GDScript y del primer cambio de nombre se corrigieron antes de publicar la compilación aceptada. Se conservaron sus registros locales. Una ejecución local sin servidor gráfico persistente falló antes de crear el consumidor; se corrigió el lanzador y no se contó esa ejecución como prueba gráfica del motor.

La primera exportación Android produjo y firmó una APK de 30.7 MB que omitía los datos: el marcador `.gdignore` del preparador de escritorio impedía enumerar las capturas, incluso con filtros explícitos. La comprobación independiente del contenido rechazó esa APK antes de entregarla. El preparador Android retira ahora sólo ese marcador en su copia de trabajo; los archivos fuente permanecen intactos. Se conserva el artefacto fallido de la ejecución `42390170223` para auditoría y no se presenta como una aplicación utilizable.

## Reproducción

```bash
python -m pip install -r requirements-hq.txt
python tools/lie_construction_android_input.py --archive artefacto-v6.zip --output /ruta/escena-v6
python tools/lie_light_field.py
python tools/lie_field_quality_cases.py
python tools/lie_hardware_build.py --cache /ruta/cache --platform linux.x86_64
python tools/lie_construction_android_build.py --data /ruta/escena-v6 --stage /ruta/prueba-nueva
```

Importar la escena preparada con Godot 4.7.2 antes de ejecutar los scripts nativos. Para exportar, compilar también el módulo `android.arm64`, instalar la plantilla Android oficial con el SHA publicado en el workflow y pasar `--godot`, `--sdk`, `--keystore` y `--output` al preparador. La prueba independiente final se ejecuta con `tools/lie_construction_apk_verify.py --apk ARCHIVO --badging INFORME_AAPT`.

Referencias de API: [tiempos del servidor de render](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html), [selector de archivos nativo](https://docs.godotengine.org/en/stable/classes/class_filedialog.html), [acceso a URI mediante el selector Android](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html). Atribución y límites originales: `LIE_HQ_CONSTRUCTION_V5.md` y `LIE_CONSTRUCTION_FIELD_V6.md`. Powered by Poly Haven; ladrillo de Centre-of-Archaeology, CC BY 4.0.
