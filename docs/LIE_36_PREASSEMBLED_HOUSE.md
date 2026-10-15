# LIE-36 — Casa con muro preensamblado y materiales 0.9

## Motivo

La primera casa ensamblaba copias de registros capturados usando el compositor
LIE-28. Se veía muy granulada por mantener solamente 6.000 muestras
de alta densidad por módulo y por carecer de la respuesta de material de
WALL12 / LIE 0.9.0.

Esta iteración **no utiliza una imagen generada por IA** ni rasteriza las
mallas fuente. Los ladrillos y juntas salen del banco autenticado
`gpu_compute/assets/lie_wall04/wall_bank.zlib`: pared original ya
ensamblada con **96 ladrillos escaneados + mortero fotográfico**,
SHA-256 `f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da`.

## Arquitectura

- Planta en L, dos alturas, un anexo bajo, aberturas reales obtenidas por
  filtrado espacial de muestras, parapetos, marquesina, porche, peldaños
  y chimenea. Sin geometría fuente rasterizada.
- Cada muestra derivada conserva un índice `source-ids.bin`. Las pruebas
  comprueban **igualdad exacta bit a bit** de posición XYZ, normal,
  RGB, rugosidad y códigos originales; solo cambia el radio de
  reconstrucción, soporte de huella y qué muestras se excluyen al abrir huecos.
- Módulos de muro: **20.000 / 6.000 / 1.700 muestras** capturadas
  según el nivel de detalle. Se seleccionan por prioridad relativa
  de cámara y presupuesto GPU: **15 héroes, 60 medios, 38 lejanos**
  en la vista de prueba, total **724.600 invocaciones**.
- Se reutilizan **exactamente las funciones** comunes de
  `gpu_compute/shaders/lib/lie_opaque_brdf.glslinc` (GGX,
  Smith correlacionado y Schlick Fresnel) y
  `lie_splat_work.glslinc` (recorte conservador de la elipse),
  integradas en el compositor Vulkan independiente
  `gpu_compute/shaders/lie36_house_material.glsl`.

**Límite importante:** el transporte de radiancia LIE11/0.9 original
se define sobre los 872 nodos de UNA pared. Todavía NO está
generalizado a todos los muros rotados de esta casa.
LIE36 utiliza el BRDF óptico 0.9 bajo una fuente directa y un
relleno ambiental autoral. Tampoco se han integrado todavía
las cachés de visibilidad LIE11, el microrelieve de contacto de
WALL12 ni una red estructural/colisiones. No debe describirse
como render completo de LIE 0.9 en toda la casa.

## Pruebas

Ejecución reproducible: `.github/workflows/lie36-real-house.yml`

1. Cuatro pruebas Python: procedencia, SHA, huecos, arquitectura/budgets.
2. Importación Godot 4.7.2 de las escenas en una carpeta aislada.
3. Compilación y render Vulkan real vía Mesa **llvmpipe por software**,
   con tres capturas PNG y 19 verificaciones Godot.
4. Se prohíbe aceptar una pérdida de densidad de píxeles por
   rasterización. Al integrar LIE0.9 apareció una regresión de
   ~100 mil a ~4 mil píxeles cubiertos: se corrigió pasando la
   coordenada de fila Y **absoluta**, tal como exige el helper 0.9.
   Ahora se exige más de 60.000 píxeles cubiertos y más de
   50.000 iluminados por cámara.

Resultados de la prueba actual:

| Vista | Píxeles cubiertos | Píxeles iluminados |
|---|---:|---:|
| Frente | 88.839 | 88.839 |
| Esquina | 99.318 | 99.318 |
| Patio | 93.661 | 93.661 |

Memoria solicitada para el compositor en el laboratorio: **178.396.160
bytes** (~170 MiB), sin representar la memoria total del proceso.
**No se midió ningún FPS físico en Android**.

Las imágenes generadas por Godot se guardan como artefacto descargable del
workflow; no sustituirlas por una ilustración externa.

## Próximo paso real de calidad

Necesitamos un transporte de luz multimuros consciente de instancias:
transformar normales y posiciones por módulo, reutilizar las
propiedades ópticas y cachear factores de transporte en superficies
enfrentadas. Después mejorar oclusión de esquinas, continuidad de
relieve, carpintería y materiales de cubierta. Esa generalización
debe poder aplicarse también a posteriores edificios sin volver a
programar un shader por casa.
