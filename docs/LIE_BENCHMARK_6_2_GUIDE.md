# LIE Construcción 6.2.0: prueba de muros invisibles

1. Instala `LIE-Construccion-v6.2.0.apk`. Se instala junto a 6.1.0.
2. Abre **LIE Benchmark 6.2.0**.
3. Pulsa **Probar muros y copiar**, encima de la imagen.
4. Espera **Informe copiado**, vuelve a ChatGPT y pégalo.

La prueba compara 781 cajas por pieza con cinco volúmenes agrupados del mismo
conjunto. Comprueba pared sólida, ventana abierta y movimientos de cámara,
usando la física real del motor. Copia cantidades, tiempos CPU de consultas y
contadores de renderizado. Restaura tus ajustes al terminar.

Para experimentar manualmente:

- **Unir volúmenes** cambia entre cajas por pieza y cinco cajas para la esquina.
- **Cámara con colisión** frena los movimientos que atraviesen esas superficies.
  Empieza apagada para conservar la vista de las versiones anteriores.
- Los gestos habituales giran, acercan y desplazan la cámara.
- La escena **door** conserva una hoja física independiente: el control de
  apertura mueve la geometría visible y su caja de colisión.
- **Benchmark y copiar informe** conserva la comparación anterior de cámara,
  luz y rebotes. Mide un trabajo distinto de las consultas de física.

Las cajas no se dibujan. Las capturas, el relieve, los LOD y la resolución
predeterminada de salida 960 / interna 1920 se mantienen.

Los volúmenes agrupados simplifican juntas y pequeñas irregularidades; no son una
unión exacta del escaneo. Conservan el hueco libre de la ventana. Este primer
agrupado se aplica a **corner**; los demás conjuntos mantienen cajas por pieza.

La reducción de cuerpos de colisión no demuestra una mejora de FPS. Esta prueba
no elimina muestras del renderer ni cambia los parches de iluminación. Los
tiempos del informe son los de tu teléfono; los de Vulkan software en CI solo
validan la integración y las imágenes. No se declara alcanzado 60 FPS.
