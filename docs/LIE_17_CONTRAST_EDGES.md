# LIE-17 — Suavizado de contornos por contraste

LIE-17 añade un filtro opcional a la composición final del robot de Arcont.
Mantiene el maestro, las capturas de 128×128, los niveles adaptables, el
renderizado interno de 384×384 y el historial de LIE-16. Solo la composición
de la salida cambia: no se añade una imagen intermedia ni un nuevo despacho.

El contraste se mide con luminancia perceptual aproximada. En regiones de
contraste suficiente, cuatro vecinos diagonales estiman una dirección de
contorno. El filtro toma muestras estrechas y anchas en esa dirección, con
desplazamientos acotados a un píxel respecto al centro. Se conserva el centro
cuando el contraste es bajo o la dirección es indeterminada. Así se evitan
promedios indiscriminados y se conservan texeles aislados/líneas estrechas en
los casos de prueba. Esto sigue siendo una aproximación de imagen.

Cada lectura mantiene las comprobaciones de alfa, profundidad finita/positiva
y oclusión por la escena nativa. El filtro solo lee la imagen Lie inmutable;
no lee colores de píxeles vecinos de la escena que otros hilos están escribiendo.
La escena de fondo usada es siempre la del píxel de salida actual. La interfaz
se dibuja después. El laboratorio permite activar/desactivar el filtro.

`gpu_compute/lie17_lab.tscn` conserva los controles y modos de calidad de LIE-16.
El historial está activo por defecto. `set_edge_aa()` sincroniza el control con
el hilo de renderizado; no cambia los buffers ni el historial geométrico.
Los hooks añadidos al consumidor LIE-16 conservan su shader y política anterior.

## Validación reproducible

Tras preparar el mismo paquete de capturas de LIE-16:

```bash
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute --script res://test_lie17_edges.gd
godot --path gpu_compute res://lie17_lab.tscn
python3 tools/lie17_evidence.py EXTRACTED_ARTIFACT OUTPUT_DIRECTORY
```

Once casos ejecutan el shader real. Tres contornos diagonales se comparan con
el área exacta de cada píxel, calculada recortando un cuadrado con un semiplano;
este oráculo no reproduce el algoritmo del filtro. Otros casos comprueban
color constante, un texel aislado, una línea de un texel, profundidad inválida,+alfa vacío, oclusión nativa completa/parcial y superficie visible delante de
la escena nativa.

Las grabaciones comparan 48 pares reales con idéntica cámara, pose y entrada
espacial. Desactivan temporal/jitter para aislar el filtro de bordes; no son
una medida del efecto combinado con historial. Los 25 fps elegidos para la
exportación son cadencia de presentación, no rendimiento del motor.

La prueba de coste usa bloques apagado/encendido/apagado, conserva 12 intervalos
del consumidor por bloque y permite revisar la deriva. El intervalo incluye
reconstrucción, resolución temporal en modo paso directo y composición; excluye
transporte de luz y grafo de poses CPU. No hay descargas de imágenes ni escritura
PNG dentro de los bloques medidos. `lie17-diagnostic.json` conserva los datos.

## Coste y límites

El filtro añade lecturas de textura y operaciones por píxel. No es gratuito
y no recupera detalle que falta en las capturas. Puede suavizar detalles finos;
los casos sintéticos no garantizan conservación de todo asset futuro. Una
reserva de memoria idéntica no implica idéntico tiempo. Los resultados Vulkan
de CI son del driver de software llvmpipe; falta medir GPU física y Android.

La prueba se inspira en detección de contraste y filtrado orientado en espacio
de pantalla de [FXAA, Timothy Lottes/NVIDIA](https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf).
Es una variante propia acotada para la composición Lie, con rechazo de profundidad;
no implementa los presets ni la búsqueda completa de extremos de FXAA.
