# LIE-25 · Capturas anatómicas por capas

Un busto del maestro gratuito 3DAnatomyman conserva piel, músculos, huesos e
interiores como cuatro bancos de muestras neutras. La misma profundidad decide
qué tejido se ve. Ocultar piel deja visibles muestras internas capturadas por
separado; cambiar pigmento o luz no requiere volver a capturar el modelo.

La prueba usa giro rígido. No añade expresiones faciales, piel texturizada,
cortes, bordes de heridas ni un sistema de gore.

## Maestro y procedencia

- Autor: Always3D; derivado de BodyParts3D © Database Center for Life Science.
- Fuente: <https://always3d.gumroad.com/l/haJWL>, cupón `free-always3d`.
- Licencia del maestro y de las capturas derivadas: CC BY-SA 2.1 JP.
- Archivo: `3DAnatomyman_English.blend`, 703,830,766 bytes (671.225 MiB),
  Blender 2.80 comprimido; abierto con Blender 4.3.2.
- SHA-256: `a47d7ea9ae4082b793d4d45761c4c73db96707bb5f03c279b4133053c6c3e193`.
- Inventario: 934 meshes, 16,189,200 vértices y 26,317,506 polígonos.
  Cuatro materiales grises constantes, sin mapas de color ni armature.
  Sus Principled tienen metalicidad 1; la prueba usa tejidos dieléctricos.

Conservar el README original con el maestro. Advierte que pueden existir
intersecciones y huecos entre órganos, y que vasos y tráquea no necesariamente
son huecos. Quitar una capa no produce automáticamente un corte cerrado.
La adquisición se hace aparte. El repositorio no guarda correo, recibos ni
enlaces privados de entrega. El importador exige la identidad inspeccionada.

## Captura y soporte

El recorte abarca los 38 cm superiores de la piel en coordenadas mundiales
Blender Z-up, convertidas a Lie Y-up. Se excluyen pelo y cejas para tratarlos
como assets con pigmentos propios. Se liberan las piezas bajo el recorte y
se triangulan solo sus polígonos retenidos, preservando sus posiciones.

Cada capa tiene 36 vistas: doce azimuts y tres elevaciones. Piel y músculos
usan 192²; huesos usan 288² e interiores 448² para las estructuras finas.
Los NPZ conservan imágenes de gris neutro, normales y profundidad, así como
las bases reales de sus cámaras. La huella es 0.45 pasos de captura en piel y
músculos; 0.38 en huesos y 0.40 en interiores.

Las muestras guardan XYZ local, normal, huella y tejido. Una caja de ocho
vértices y doce triángulos registra la envolvente invisible; nunca se dibuja.
Cada XYZ capturado recibe el mismo giro global: no se interpola sobre esos
triángulos ni se ha añadido un collider físico. Esto ahorra geometría de
control, no elimina la memoria de muestras. El contrato
`lie-anatomy25-rigid` es independiente del de los ojos y narices.

| ID | Capa | Bit de visibilidad |
| --- | --- | --- |
| 0 | Piel | 1 |
| 1 | Músculos | 2 |
| 2 | Huesos | 4 |
| 3 | Interiores | 8 |

`mask=15` muestra todas; `14` quita piel; `12` deja huesos e interiores;
`8` muestra interiores; `0` oculta todo. La capa inactiva no proyecta muestras
ni escribe sombra. La selección no establece prioridad de dibujo: la
profundidad común y el propietario final resuelven la superficie visible.
La reconstrucción de material no mezcla tejidos distintos.

La paleta es RGB lineal por tejido, separada de la luz. La iluminación hereda
el consumidor LIE-23: fuente puntual, normales capturadas, GGX dieléctrico,
sombras desde muestras y término ambiental. No se afirma transporte indirecto
anatómico ni apariencia equivalente a Cycles. Un color uniforme no sustituye
poros, vascularización, pigmentación local o mapas de rugosidad.

## Reproducción y controles

```sh
blender --background --disable-autoexec --python-exit-code 1 \
  --python tools/lie25_prepare_blender.py -- \
  --input /absolute/3DAnatomyman_English.blend \
  --out gpu_compute/captures/anatomy25 \
  --resolution 192 --detail-resolution 288 --internal-resolution 448
godot --headless --path gpu_compute --editor --import --quit
godot --path gpu_compute --rendering-driver vulkan \
  --rendering-method forward_plus --script res://test_lie25_anatomy.gd
python3 tools/lie25_compare_native.py gpu_compute
godot --path gpu_compute res://lie25_anatomy_lab.tscn
```

El laboratorio expone selección de capas, pigmentos, cámara, giro y luz.
Su método `command` comparte la misma operación atómica con los controles:

```json
{"op":"set_values","values":{"mask":14,"light_azimuth":65}}
```

Acepta `snapshot` y `expected_revision` para evitar sobrescribir ediciones.
No integra aún documentos guardados, historial o inbox del taller facial.
El banco se carga una vez y el resultado inmóvil queda residente.

## Verificación y límites

Vulkan comprueba propietarios de capas activas, restauración idéntica de
imagen, giro de muestras, cambios reales de color y luz sin nuevas subidas,
imagen vacía al ocultar todo y rechazo atómico de parámetros inválidos.

Referencias independientes lanzan rayos de perspectiva contra las superficies
detalladas recortadas en Blender, sin utilizar los puntos capturados ni el
algoritmo de splats. Se exige IoU de silueta ≥ 0.985 y MAE de RGB sin luz
≤ 0.03 para cada selección. Se informa cada resultado por separado.

Solo se compara la vista frontal de estas cuatro selecciones. La prueba
de giro valida coordenadas, no la calidad visual desde todos los ángulos.
FPS en Android, GPU física, cuerpo completo animado, reutilización entre
múltiples personajes y cortes siguen sin medirse o implementarse.

La memoria del banco y la reserva del compositor se informan aparte del tamaño
de descarga. Vulkan por software comprueba comportamiento, no rendimiento de
hardware ni viabilidad móvil. Tampoco equivale a validar realismo anatómico.
