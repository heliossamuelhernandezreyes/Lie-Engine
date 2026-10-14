# WALL05: maestro compartido y códigos ópticos en Android

Implementación experimental del concepto de [propagación óptica compartido
por el autor](https://chatgpt.com/share/6acfe0bb-18b0-83e8-87ca-7a4b9c8163bf).
Parte del APK WALL04 que el autor observó a 36–60 FPS en su Poco X7 Pro.
Esas cifras no son medidas de esta nueva versión.

## Acceso e instanciación

El banco contiene **una copia neutral original de LIE-BRICK02** (281,000
muestras, 22,480,000 bytes) y las muestras originales de mortero fotografiado
(19,220,560 bytes). No contiene 96 copias transformadas del ladrillo. Los
96 registros de instancia guardan pose/tinte y usan una tabla de índices
para elegir exactamente los mismos subconjuntos por LOD que WALL04.
El mortero es el consumidor número 97. El banco ocupa **41,700,560 bytes**;
los índices, **3,088,388**. Antes eran 61,767,760 bytes de banco precompuesto.
Cada acceso es ID de instancia + índice de muestra hacia un búfer GPU
residente; no se busca una foto ni se lee almacenamiento por píxel.

El maestro neutral y el mortero se verifican por SHA y se conservan sin
alterar. El reconstruido virtual obtiene las transformaciones/tintes/radios
del autor original. La prueba Python compara todos los registros virtuales
con el WALL04 bloqueado, bit por bit. El shader usa los mismos campos de
80 bytes y procesa muestras originales; no dibuja la malla de 500,000
triángulos. La pared conserva **una sola BoxShape3D invisible**.

## Cachés separadas

- Cambiar cámara/LOD/pose reconstruye proyección, profundidad, propietarios,
  acumulación y recuperación fotográfica.
- Cambiar luz, absorción o la política óptica reutiliza esos datos. Una
  recuperación válida almacena coeficientes RGB por código de luz para
  iluminar después sin buscar vecinos otra vez.
- Cambiar solo exposición ejecuta la salida final.
- Una imagen inmóvil se reutiliza sin ejecutar reconstrucción.

La caché de recuperación admite 65,536 píxeles reparados. Si se excede,
los restantes conservan la búsqueda fotográfica original; no se inventa
cobertura. Los coeficientes respetan grupo, normales, profundidad y soporte
originales. El registro de proyección de 96 bytes conserva además el ID de
luz, el soporte y su eje: las fases de iluminación y recuperación acceden a
ellos sin reconstruir muestras neutrales por cada píxel vecino.

El modo equilibrado calcula a **1080 × 1080** con salida **720 × 720**.
La opción **Supermuestreo 2×** vuelve a 1440 × 1440. Cambiarla conserva el
RID de salida y el banco compartido, y reemplaza solo los búferes de trabajo.
Los contadores de pantalla distinguen FPS, reconstrucciones, cálculos de luz
y reutilizaciones. Los bytes solicitados al RenderingDevice no son PSS del
proceso ni porcentaje de uso de GPU.

## Conexión óptica LIE35 → escena

La nueva especialización conserva los 872 nodos y la visibilidad CSR fuente.
Una transpuesta del mismo grafo permite calcular límites de energía por
emisor/lóbulo. Los códigos ópticos agrupan normales, RGB lineal y rugosidad
**de las muestras reales de los 872 nodos**. Metalicidad 0, transmisión 0,
IOR 1.5, espesor 0 y extinción 0 son datos de autoría explícitos para arcilla
y mortero opacos; no se deducen de las fotografías.

La frontera guarda energía incidente y una dirección media ponderada por
potencia. La distribución difusa y el lóbulo reflejado aproximado de LIE35
reemplazan el factor angular de emisión una vez. Fresnel/reflectancia y
absorción delimitan los presupuestos, y cada lóbulo se limita por sus
conexiones salientes. Cada generación consume solamente la anterior:
la energía acumulada nunca vuelve a emitirse como una nueva fuente.
La salida sigue siendo la irradiancia RGB del mismo transporte, consumida
por el compositor existente.

**Límites:** la pared mantiene un grafo opaco. La refracción/transmisión de
vidrio continúa en el experimento LIE35 aislado; no se añadieron caminos
refractados a WALL05. El lóbulo reflejado es una aproximación angular, no
una solución GGX completa, ni un trazador de cáusticas. Una dirección media
no conserva mezclas angulares de múltiples luces. La visibilidad y las
normales de cuadratura siguen siendo aproximadas. Se requiere una comparación
con Cycles para certificar calidad física o fotorealismo.

## Inclinación y franjas

La cara frontal original del escaneo tiene inclinación medible. Los viejos
AABB de sombra no representan esa cara irregular. La opción **Sombras según
cara escaneada** recorta esos oclusores con un plano interior calculado de
23,102 muestras frontales, percentil 5 y separación de 1.5 mm. Es información
para luz, no una superficie visible ni un collider nuevo. La sombra propia
de la caja sigue excluida como en WALL04.

La geometría conserva el escaneo. **Enderezar físicamente la cara y recalibrar
el mortero siguen pendientes**; no se deforma silenciosamente el banco para
ocultar franjas. Tampoco se certificaron las máscaras G1 o escala absoluta
del relieve del mortero. La prueba registra el cambio en píxeles negros y
conserva las capturas para comprobar cuánto mejora y qué queda.

## Evidencia y construcción

El checkpoint JSON adjunto identifica el commit de código, el run nativo,
las comparaciones de imagen, el error CPU/GPU, los contadores, la memoria,
las capturas y el APK. Las pruebas son Vulkan Mobile con llvmpipe, no un
Android físico. Los tiempos se clasifican por geometría/luz/exposición:
no se mezclan en una supuesta cifra de FPS de juego.

```sh
python tools/lie_wall05_shader.py
python tools/lie_wall05_optical_shader.py
python -m unittest discover -s tests -p 'test_lie_wall05*.py' -v
python tools/lie_wall05_android_build.py --stage /tmp/lie-wall05 \
  --godot /ruta/Godot_v4.7.2-stable_linux.x86_64 \
  --sdk /ruta/android-sdk --keystore /ruta/debug.keystore \
  --output /ruta/LIE-Pared-0.2.0.apk
```

Godot 4.7.2, JDK 17 y Android Build Tools 36.0.0. El APK offline ARM64 usa
`org.lieengine.wallruntime.v020`, nombre **LIE Pared 0.2**, para instalarse
junto al APK anterior y compararlos. Conserva atribuciones CC BY 4.0, CC0 y
licencia Godot. Se verifican plantilla oficial, firma v2/v3, alineación
16 KiB, manifiesto e integridad/SHA de los bancos dentro del APK.

La importación de shaders se hace en serie: Godot 4.7.2 llama una comprobación
de visibilidad del editor desde un worker cuando se importa en paralelo.
La configuración evita esa infracción de hilo sin cambiar el núcleo ni
ignorar mensajes de error en las pruebas.

Fundamento y límites de reflexión/energía:
[PBRT: Surface Reflection](https://pbr-book.org/4ed/Radiometry%2C_Spectra%2C_and_Color/Surface_Reflection),
[PBRT: Roughness Using Microfacet Theory](https://pbr-book.org/4ed/Reflection_Models/Roughness_Using_Microfacet_Theory).
Un material pasivo debe conservar energía; un lóbulo angular aproximado por
sí solo no demuestra una BSDF física completa.
