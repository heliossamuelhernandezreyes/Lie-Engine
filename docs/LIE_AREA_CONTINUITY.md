# LIE área y continuidad — trabajo en curso

Base validada: ce2816730f3afafce8c739c7537358f58df9ac81 (0.9).
El entorno perdió los cambios locales anteriores a su publicación; este hito se reconstruye desde esa base. Este primer checkpoint conserva código **sin aceptación Vulkan ni APK nueva**.

Objetivo autorizado: fusionar iluminación y composición, filtrar material guiado por propietario/grupo/normal/plano y huella, añadir emisores rectangulares y una prueba automática en Android.

El filtro espacial 3x3 reutiliza la imagen de 16 bytes/píxel como ocho valores half; no mueve profundidad ni rellena huecos. No implementa EWA completo, antialiasing temporal ni garantiza cobertura hermética. El acumulador original sigue teniendo sus propias aproximaciones de propietario.

Un rectángulo Lambert de una cara se integra con cuatro puntos Gauss-Legendre. Cada punto conserva 1/4 de la potencia total y su normal de emisión. La ganancia respecto al punto isotrópico es 4 max(cos(theta),0), coherente con Phi = pi A L. Transporte, respuesta local y sombras consumen los mismos puntos. Dos rectángulos ocupan los ocho canales disponibles; se rechaza una capacidad mayor antes de mutar el registro. Las unidades son metros y potencia RGB lineal relativa, no lúmenes medidos. Cuatro puntos pueden dejar escalones de penumbra y no resuelven toda integral próxima u ocluida.

Se mantienen el banco fuente aceptado, sus IDs de 80 bytes, las instancias, la caja física y la extensión RenderingDevice existente. No hay fork de Godot.

Referencias primarias: [PBRT 4: Area Lights](https://www.pbr-book.org/4ed/Light_Sources/Area_Lights), [MERL: Object Space EWA Surface Splatting](https://www.merl.com/publications/TR2002-31). Esta última orienta el uso de huellas; el filtro implementado no equivale a su algoritmo.

Pendiente: terminar pruebas sintéticas del filtro y pruebas integradas de imágenes/caché, compilar shaders, ejecutar Vulkan real y regresiones CPU, verificar APK firmada y registrar resultados incluyendo fallos. Ningún tiempo de Vulkan software se debe presentar como FPS del Poco.
