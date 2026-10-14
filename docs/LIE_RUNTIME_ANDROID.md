# LIE Pared 0.1.0 para Android

APK offline ARM64, paquete independiente `org.lieengine.wallruntime`.
Se instala junto al laboratorio R2 sin sustituirlo. El proyecto se prepara
en una carpeta aislada y conserva la entrada del taller de escritorio.

Incluye el banco real WALL04 de 61,767,760 bytes, sin cambiar su SHA ni
dibujar el maestro fuente. Usa una envolvente invisible para la pared,
transporte CSR y caché de luz, con salida de 720 × 720 para esta prueba.

Utilizar en horizontal. El panel derecho se desplaza con el dedo y permite
cámara, luz, exposición, sombras y absorción. **Radio energético** alterna
la política histórica con el modo opcional de irradiancia (cutoff 0.001,
radio máximo 6 m y decrecimiento 0.82). Todos los controles pasan por el
`command()` validado; volver al modo histórico restaura los píxeles de partida.

La pantalla distingue FPS de la aplicación y reconstrucciones LIE por
segundo: mostrar una imagen en caché no significa reconstruirla cada frame.
Los bytes de búferes mostrados no representan PSS total ni utilización GPU.

El APK se verificó con apksigner v2/v3, zipalign a 16 KiB, aapt, integridad
ZIP y SHA del banco dentro del propio APK. La plantilla oficial Godot 4.7.2
tiene SHA `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.
Se conservan la atribución CC BY 4.0 del escaneo de Centre-of-Archaeology,
la procedencia CC0 del mortero Poly Haven y la licencia de Godot dentro del APK.
El manifiesto se normaliza antes de realinear y firmar: mismo arreglo
de tipos Vulkan y autoridad Startup usado por el prototipo Android R2.

El [run 38608032842](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38608032842)
pasó 11 comprobaciones del proyecto aislado con el renderizador **Mobile**
y Vulkan por software: escena y transporte reales, controles válidos,
rechazo atómico de un radio inválido, restauración exacta de píxeles y banco
subido una sola vez. No sustituye una ejecución en el Poco ni establece FPS
de hardware físico. El mortero conserva sus limitaciones visuales pendientes.

Los 18 workflows del commit de código terminaron aprobados. LIE22 necesitó
repetir su job sin cambiar código: la profundidad del hueco tras destruir
un ladrillo falló en el primer intento y pasó los 56 checks en el segundo.
Esta variabilidad queda registrada; ese laboratorio no forma parte del APK.

Compilación reproducible:

```sh
python tools/lie_wall04_compose.py --restore
python tools/lie_runtime_android_build.py --stage /tmp/lie-wall-stage \
  --godot /ruta/Godot_v4.7.2-stable_linux.x86_64 \
  --sdk /ruta/android-sdk --keystore /ruta/debug.keystore \
  --output /ruta/LIE-Pared-0.1.0.apk
```

Requiere la plantilla Android debug oficial, JDK 17 y Android Build Tools
36.0.0. Solo se copia el cierre de dependencias de código y el banco WALL04,
evitando otros grandes experimentos. El reporte de construcción y el SHA
del APK están en `checkpoints/LIE_RUNTIME_ANDROID_CHECKPOINT.json`.
