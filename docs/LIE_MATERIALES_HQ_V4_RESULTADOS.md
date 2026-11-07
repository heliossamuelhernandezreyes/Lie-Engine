# Validación del banco fotográfico HQ v4

Código validado: `8df2176523736dfec8a9a4df4850652e1ae41a2f`.
[CI independiente](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/42347822320),
job `128329289085`: **correcto**. 279 pruebas CPU: 278 correctas y una omisión;
**94 comprobaciones nativas** correctas. Godot 4.7.2: llvmpipe LLVM 19.1.7 local
y LLVM 21.1.8 en CI. No se ha medido Android.

| Material | Cobertura interior | PSNR RGB | RMSE de profundidad | MAE de EXR frente a JPEG 8K sRGB |
|---|---:|---:|---:|---:|
| concrete_layers | 99.8582% | 30.601 dB | 0.1336 mm | 0.00360 |
| wood_table_worn | 99.8571% | 31.693 dB | 0.0351 mm | 0.00396 |
| rock_boulder_dry | 99.8655% | 26.235 dB | 0.0954 mm | 0.00407 |
| grey_plaster | 99.8522% | 25.947 dB | 0.0520 mm | 0.00636 |

Son errores numéricos contra la superficie fuente del modelo actual, no
precisión certificada de un objeto físico. La referencia utiliza normales
geométricas, sin el mapa normal óptico. La cobertura no es 100%: quedan pérdidas
muy pequeñas por el muestreo. La aceptación numérica no certifica hiperrealismo.

Se corrigió una interpretación inicial incorrecta de los EXR como lineales.
Los cuatro mapas de color contienen valores sRGB, comprobados contra el JPEG
original 8K que el proveedor asigna como sRGB en Blender. Cada texel se decodifica
antes de interpolar. El contraste de hipótesis produce errores de 0.0036–0.0064
con la codificación correcta, frente a 0.19–0.26 al asumir color lineal.

Se corrigió además el límite de despacho: 2048² píxeles requieren 65536 grupos,
uno más que el límite X garantizado de Vulkan. Los kernels de este consumidor
aplanan un despacho bidimensional; los consumidores anteriores conservan sus
rutas por defecto. Los perfiles, LOD, conjuntos y liberación de bancos compartidos
se probaron en el render nativo.

Los bancos son SHA-dependientes. Compilaciones en plataformas distintas pueden
diferir en los últimos bits de la conversión flotante del color; cada conjunto
se enlaza al SHA de su propia compilación. No se mezclan recetas y bancos de
artefactos distintos. Los originales permanecen fijados por sus hashes.

Artefacto CI `13563803975`: 246,976,521 bytes,
SHA-256 `984ae24cfca9fb735e6c914d2a634aeb6b60325db4e0f6176fa5ff4d79da2e11`.

Banco distribuido: 246,069,015 bytes,
SHA-256 `195179d2618b31fde069c57c4d9dec975a0d9c237ec9169bafc3cbd4592ca5cc`.
Contiene datos compilados y evidencias. El código se conserva en Git.

## Archivos disponibles

- `LIE_Banco_Materiales_HQ_v4.zip`
- `LIE_HQ_Fuente_concrete_layers_8K.zip`
- `LIE_HQ_Fuente_wood_table_worn_8K.zip`
- `LIE_HQ_Fuente_rock_boulder_dry_8K.zip`
- `LIE_HQ_Fuente_grey_plaster_8K.zip`
- `LIE_Materiales_HQ_v4.png`

Los paquetes fuente incluyen el Blender original intacto y una variante
`source-relinked.blend` con las rutas adaptadas a los archivos archivados.
El banco amplía la biblioteca; no sustituye los maestros previos ni actualiza
la APK. La integración de normales ópticas y las superficies continuas para
casas siguen pendientes y se describen en la guía v4.
