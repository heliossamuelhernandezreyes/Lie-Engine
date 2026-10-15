# LIE37 — Casa real con transporte RGB entre muros

## Ejecución reproducible

Rama: `experiment/lie36-real-scan-house`; PR #55. No cambia el motor de producción.
Prueba CI: [run 38718214216](https://github.com/heliossamuelhernandezreyes/Lie-Engine/actions/runs/38718214216).
Vistas PNG reales: `docs/captures/lie36/`.

Se conserva el banco WALL04 ya ensamblado y su SHA-256 original
`f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da`.
No hay caras de la malla origen dibujadas, materiales fabricados por una IA,
ni fotografías falsas como resultado de Godot.

## Qué se implementó realmente

- Shader `gpu_compute/shaders/lie36_house_material.glsl`:
  conserva el BRDF GGX/Smith/Fresnel de LIE0.9 y la rasterización conservadora.
- **Fase 8:** irradiancia RGB directa por cada panel transformado; oclusión
  contra otros paneles de la casa, respetando los huecos de puertas y ventanas.
- **Fase 9:** grafo de transferencia orientado fuente-receptor,
  distancia-cuadrado y visibilidad entre paneles. Por fuente se
  normalizan sus pesos a suma <= 1, evitando emitir más potencia que la
  disponible en cada uno de los canales RGB.
- **Fase 10:** un rebote difuso del flujo iluminado utilizando albedo auténtico
  aproximado de las muestras originales, áreas de panel y pesos dirigidos.
- **Fases 11–12:** cierre opcional de huecos de **un solo píxel**, solamente
  cuando existen muestras reales a ambos lados con profundidades, normales
  y colores compatibles. No crea geometría ni cierra grandes aperturas.
- `gpu_compute/lie36_house_effect.gd`: enlaza estos pases con la
  reconstrucción GPU y presenta lecturas instrumentadas de enlace/energía.
- `gpu_compute/lie36_house_lab.gd`: controles reversibles
  `bounce` y `seams`, sin tocar el banco de escaneos.
- `gpu_compute/test_lie36_house.gd`: comprobación de capturas y A/B nativos
  con cámara y dirección de luz idénticas.

## Resultado de GitHub Actions: verificado

- 4 pruebas Python aprobadas para SHA/origen real, huecos y arquitectura.
- 29 comprobaciones nativas Godot 4.7.2 sobre Vulkan llvmpipe: **aprobadas**.
- 113 instancias; 110.800 muestras en biblioteca compartida;
  724.600 invocaciones por reconstrucción (LOD 15/60/38).
- 6.787 enlaces de transporte activos; 112 de 113 paneles reciben
  contribución difusa rebotada; 0 infracciones energéticas detectadas
  (máximo de suma por fuente 1.00000037 por redondeo de float32).
- Los estados de `bounce` activado/desactivado dan píxeles GPU diferentes.
  Igual para `seams`.

| Cámara | Cobertura previa | LIE37 | Incremento |
| --- | ---: | ---: | ---: |
| Frente | 88.839 | 89.969 | +1.130 (+1.27%) |
| Esquina | 99.318 | 100.467 | +1.149 (+1.16%) |
| Patio | 93.661 | 94.654 | +993 (+1.06%) |

A/B comparado sobre la misma vista de patio, imágenes de salida 512²:
la ausencia de rebote altera 102.500 píxeles RGB (media de
15,53 unidades de 8 bits en los píxeles cubiertos), y desactivar
el rescate de costuras altera 3.602 píxeles RGB.

Recursos solicitados por el compositor: 178.465.792 bytes
(~170,2 MiB), **no memoria total de Godot/Android**.

## Límites pendientes

Este es un **modelo aproximado de un rebote difuso a nivel de panel**
sobre topología de 113 superficies y oclusión de planos. **No** es
todavía el transporte completo de micromuestras/872 nodos de WALL12,
ni luz especular multirrebote, ni oclusión volumétrica precisa de cada
saliente. No se midieron FPS, energía o temperatura en un móvil real.
La cubierta, las uniones y el aspecto final de la casa necesitan
materiales y geometría local mejor ensamblados, sin eliminar
el origen fotográfico.

El criterio de aceptación es reproducible, no una declaración de que
el resultado ya iguala el detalle visual del WALL12 maestro.
