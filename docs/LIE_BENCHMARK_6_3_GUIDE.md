# LIE Construcción 6.3.0: cámara y selección de muestras

1. Instala `LIE-Construccion-v6.3.0.apk` y abre **LIE Benchmark 6.3.0**.
   Se instala junto a las versiones anteriores.
2. Pulsa **Probar jerarquía y copiar**, encima de la imagen.
3. Espera **Informe copiado**, vuelve a ChatGPT y pégalo.

La prueba recorre dos trayectorias: una vista del conjunto y otra cercana al
muro. Repite exactamente los mismos giros con la selección apagada y encendida.
El informe distingue muestras de cámara, muestras de sombra, tiempos GPU de
apariencia, intervalos de imágenes y tiempo de comandos. Restaura tus ajustes
al terminar. El primer bloque sirve de referencia: la mejora depende del
encuadre y puede ser pequeña si se ve el conjunto completo.

**Probar muros y copiar** compara por separado 781 cajas físicas con 13 cajas
agrupadas. Comprueba pared sólida y ventana libre con consultas del motor.
Los tiempos CPU de esas consultas no son FPS de renderizado.

Controles para experimentar:

- **Unir volúmenes:** activa cinco zonas del cuerpo de los muros más dos
  zócalos y seis piezas del marco, alféizar y dintel. El agrupado corresponde a
  `corner`; otros conjuntos conservan sus cajas por pieza.
- **Cámara con colisión:** evita atravesar los volúmenes, desliza el movimiento
  restante por la pared y recupera una posición inicial solapada cuando existe
  una salida entre los candidatos comprobados. Empieza apagada.
- **Selección visible:** activa la jerarquía conjunto → muro → tramo → pieza.
  Empieza encendida. Conserva las piezas que cruzan los bordes del encuadre.
- **Benchmark y copiar informe:** conserva la prueba de cámara, luces y
  rebotes. Sirve para comparar con los informes anteriores.

Las cajas físicas no se dibujan. La selección usa los límites de las páginas de
captura, separados de las envolventes físicas. Omite muestras de cámara fuera
del encuadre; mantiene todas las piezas para las sombras y para el campo de
iluminación, aunque estén fuera de cámara. No elimina todavía objetos tapados
por otros muros dentro del encuadre.

Se conservan los mismos archivos de captura y LOD de las versiones anteriores.
La salida predeterminada sigue siendo 960 × 960 con reconstrucción interna
1920 × 1920. No hay una reducción automática de calidad para obtener mejores
tiempos.

Las cajas siguen siendo aproximaciones del relieve y de las juntas. La cámara
usa un radio de 2.5 cm, una separación de 2 mm y hasta cuatro contactos por
movimiento. Los bordes redondeados se aproximan conservadoramente; puede
detenerse algo antes en una arista diagonal. La recuperación se informa como
una corrección de posición, no como un desplazamiento continuo sin contactos.

La validación con Vulkan software comprueba integración e imágenes; los FPS
sostenidos y la temperatura deben medirse en tu teléfono. El informe no
inventa frecuencia ni temperatura GPU cuando Android no permite leerlas.

## Resultado de la validación

Se aprobaron 65 comprobaciones de física/jerarquía y 53 de integración gráfica.
Las diez imágenes de referencia coinciden exactamente con 6.2.0. Las pruebas
de selección también conservaron color, profundidad y sombras. En la vista
cercana probada a 960/1920 se procesaron 392,960 de 1,165,568 muestras de
cámara: 66.3 % menos. Se conservaron las 1,165,568 muestras para sombras.
En la vista completa permanecieron todas las muestras, como corresponde.

También se corrigió la preparación del campo del techo: conserva sus 148
nodos y 62 conexiones, y ya configura la escena nueva. Esta corrección no
cambia los materiales ni reduce su detalle.
