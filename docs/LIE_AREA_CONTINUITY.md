# LIE área y continuidad — trabajo en curso

Base validada: ce2816730f3afafce8c739c7537358f58df9ac81 (0.9).
El entorno perdió los cambios locales anteriores a su publicación; este hito se reconstruye desde esa base. Este primer checkpoint conserva código **sin aceptación Vulkan ni APK nueva**.

Objetivo autorizado: fusionar iluminación y composición, filtrar material guiado por propietario/grupo/normal/plano y huella, añadir emisores rectangulares y una prueba automática en Android.

El filtro espacial 3x3 reutiliza la imagen de 16 bytes/píxel como ocho valores half; no mueve profundidad ni rellena huecos. No implementa EWA completo, antialiasing temporal ni garantiza cobertura hermética. El acumulador original sigue teniendo sus propias aproximaciones de propietario.

Un rectángulo Lambert de una cara se integra con cuatro puntos Gauss-Legendre. Cada punto conserva 1/4 de la potencia total y su normal de emisión. La ganancia respecto al punto isotrópico es 4 max(cos(theta),0), coherente con Phi = pi A L. Transporte, respuesta local y sombras consumen los mismos puntos. Dos rectángulos ocupan los ocho canales disponibles; se rechaza una capacidad mayor antes de mutar el registro. Las unidades son metros y potencia RGB lineal relativa, no lúmenes medidos. Cuatro puntos pueden dejar escalones de penumbra y no resuelven toda integral próxima u ocluida.

Se mantienen el banco fuente aceptado, sus IDs de 80 bytes, las instancias, la caja física y la extensión RenderingDevice existente. No hay fork de Godot.

Referencias primarias: [PBRT 4: Area Lights](https://www.pbr-book.org/4ed/Light_Sources/Area_Lights), [MERL: Object Space EWA Surface Splatting](https://www.merl.com/publications/TR2002-31). Esta última orienta el uso de huellas; el filtro implementado no equivale a su algoritmo.

Pendiente: terminar pruebas sintéticas del filtro y pruebas integradas de imágenes/caché, compilar shaders, ejecutar Vulkan real y regresiones CPU, verificar APK firmada y registrar resultados incluyendo fallos. Ningún tiempo de Vulkan software se debe presentar como FPS del Poco.

## Contratos e invalidación

`lie_area_emitter_codes.gd` es el compilador común de emisores. Los IDs de escena son lógicos (`key`, `fill` en este laboratorio); los canales de integración añaden `/q0..q3`. Las dimensiones y orientaciones no se deducen del asset. El marco del mundo y de la luz es rígido y métrico. Cambiar solo el tamaño actualiza las posiciones de los cuatro rayos; la caché de visibilidad compara esas posiciones. Cambiar orientación sin mover un rayo conserva su visibilidad geométrica pero recalcula la emisión. Cambiar potencia conserva visibilidad y material.

`lie_area_light_transport.gd` añade 128 bytes de descriptores de emisión al transporte común. El consumidor toma prestado el mismo RID; nunca lo libera. La ampliación de canales se reserva en la capacidad ya existente. Un hook pequeño del padre entrega los metadatos junto con el paquete de luces, antes de inicializar/despachar. Las actualizaciones pendientes conservan el indicador de invalidación mediante OR, incluso si una actualización posterior solo cambia potencia. El adaptador WALL13 es el único que conoce la ruta de los paquetes de la pared.

El filtro verifica igualdad de instancia y grupo de autoría, acuerdo de normales geométricas (coseno >= .95), y profundidad de ambos planos evaluada en el MISMO centro de píxel mediante la proyección recíproca original. La tolerancia métrica es 1.25 huellas de píxel, acotada a 0.4–2 mm. Pondera proximidad espacial y diferencia de albedo lineal. Solo lee vecinos con ganador real; no inventa muestras. Sus ocho componentes se empaquetan en cuatro uint mediante half floats. La imagen 8 cambia de formato FLOAT a UINT conservando sus 16 bytes/píxel; también se respeta el formato durante el cambio a 1440.

El material se construye al cambiar la geometría o activar/desactivar el filtro y se reutiliza al mover luces. Cambiar el filtro invalida los coeficientes de recuperación fotográfica; se regeneran desde las mismas muestras sin reproyectar. La recuperación conserva las reglas y límites existentes de WALL12. Los píxeles recuperados no adquieren una nueva profundidad física.

En modo fusionado la etapa 4 escribe albedo por irradiancia directamente en la salida; la etapa 6 no se despacha. En modo separado se conserva una comparación efectiva: usa la imagen 9 para irradiancia cuando la 8 contiene el material, o la 8 para irradiancia si el filtro está apagado. La etapa de BRDF y contactos sigue después de la recuperación y conserva la separación directa/indirecta previa. No se suman dos luces nativas sobre la misma energía.

## Prueba reproducible en el dispositivo

El botón «Medir cuatro modos» pasa por el mismo contrato `command()`: punto/separado/crudo, punto/fusionado/crudo, punto/fusionado/filtrado y área/fusionado/filtrado. Recorre ángulos de cámara, fuerza una reconstrucción de geometría y guarda el serial de cada evento para relacionarlo con las filas de timestamps GPU. No lee imágenes de la GPU. La latencia del evento incluye CPU, planificación y vsync; el FPS mostrado incluye cuadros estáticos cacheados. Los tiempos de los pases se deben comparar con igual resolución y opciones. No hay una cifra universal de FPS ni un objetivo térmico validado.

El resultado incluye dispositivo, adaptador, resolución, modos, seriales, filas crudas y comprobación de restauración del estado. Se guarda en `user://lie-benchmark-last.json` y se puede copiar desde la interfaz. La prueba corta usa dos ángulos por modo; la completa usa siete. Cancelar también restaura los ajustes. Mientras corre, la ruta pública rechaza cambios de controles que invalidarían la comparación.

## Verificación local previa a Vulkan

Reconstrucción actual: 4 pruebas Python de emisor/integral, 3 de filtro, 6 del campo anterior; 9 contratos GDScript de emisor y 17 de comandos; rig 247, agente 25. Los shaders de área, campo y filtro compilan con el importador oficial Godot 4.7.2. Los scripts de pruebas GPU e integrada pasan compilación GDScript. Esto no sustituye su ejecución Vulkan.

Negativo local conservado: una ejecución comenzó antes de que terminara la importación del proyecto aislado y no encontró los loaders de `.glsl`; produjo errores derivados de dependencias y se interrumpió. Tras completar la importación, los tres shaders y los mismos scripts compilaron sin errores y los comandos aprobaron. No se atribuye ese intento a un defecto visual o de rendimiento de la GPU.

En la revisión de ciclo de vida se detectó que un mundo sin hijos emitentes se rechazaba antes de actualizar el registro: `valid_light_codes([])` no acepta un paquete vacío. El compilador ahora permite el snapshot lógico vacío y produce el canal oscuro previsto por el transporte. La prueba elimina todos los nodos y comprueba aceptación y potencia cero; no se permite conservar energía de una fuente retirada.

Primer CI nativo (5995e0cc5ea3bc9f37cf13d4412f56f62ee31bb0), run 38728076405 / job 116398759035: regresiones anteriores completas y filtro Vulkan 15/15 aprobados. El comparador de área intentó acceder a `legacy_merged`, mientras la fixture llama al caso `merged_legacy`; el error de clave detuvo el script y produjo timeout 124. No llegó a ejecutarse WALL13 ni a exportarse una APK. Se conserva el artefacto 11969668117, 4,584,503 bytes, SHA256 6d4ed62c50e4a091ad260f7be92be6be0fe7397d2c5d739e909ed0c029c9758e, con logs e imágenes previas. Se corrige el nombre y se priorizan las pruebas nuevas en el siguiente CI.

La comprobación headless de timeout del benchmark detectó también una diferencia de tipo al restaurar los valores iniciales heredados (`seed` int 29 frente a float 29.0). Se normalizan los defaults usando el validador público al iniciar, conservando una sola ruta de controles. El contrato de cancelación/restauración añade dos comprobaciones de comandos.

Segundo CI (2d36ea46703644f8b19019616481c6314398faec), run 38729836592 / job 116404600116: filtro 15 y campo de área 536 comprobaciones aprobadas (error máximo de campo 4.34e-8). La pared falló tres comparaciones de reutilización: máximos RGB 0.0014977 al cambiar fusión, 0.0026897 reconstruyendo geometría de área y 0.0007878 al volver a puntos. Sus MAE fueron inferiores a 1e-6 e IoU 1, pero no se relajan los umbrales. Profundidad, invalidación por tamaño, apagado, suma de fuentes, resolución y benchmark sí pasaron. Artefacto 11969453806, 857,820 bytes, SHA256 a3f8c5ca881710b1ab8034459bfa73be42019791524b24b7c0df399c421c8dbe.

El kernel sintético mostró que un roundtrip pack/unpack local no produjo todos los componentes cuantizados igual que una lectura posterior del paquete: por ejemplo rugosidad 0.8000000119 frente al half almacenado 0.7998046875. Para que ambas rutas consuman exactamente los mismos bits, la etapa 14 escribe el material y una barrera de despacho precede a la lectura desde la etapa 4. Solo se ejecuta al invalidar el material; no añade imagen de frame completo ni se repite por cambiar potencia. El test sintético replica ahora esa escritura/lectura en dos despachos y comprueba explícitamente el valor half de rugosidad. La atribución a una optimización concreta del compilador/controlador no se considera demostrada.
