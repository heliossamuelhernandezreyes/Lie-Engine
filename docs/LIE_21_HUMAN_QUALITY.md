# LIE-21 · Reconstrucción humana de mayor calidad

El laboratorio anterior conservaba la deformación, pero elegía un único
material por píxel y ampliaba capturas de 192² con bordes duros. Este paso
incrementa la densidad de las capturas, reconstruye material mediante huellas
ponderadas y resuelve una imagen HDR de 1024² a una salida de 512².

## Captura y maestro

El mismo escaneo de Lee Perry-Smith / Infinite-Realities, CC BY 3.0, conserva
las fuentes fijadas en `assets/lie20/source-lock.json`. El armature y los
correctivos mantienen su significado y limitaciones de LIE-20.

Las 36 cámaras capturan ahora 384². La captura de normales usa los frames
tangentes nativos por loop de Blender, interpolados sobre la superficie,
incluyendo la interpolación de fuerza del normal map. Se conserva el detalle
como dato de apariencia; nunca interviene en la profundidad geométrica.
Los buffers originales de vértices/triángulos solo vinculan y deforman las
muestras. No se dibuja la malla original.

```sh
blender --background --python-exit-code 1 --python tools/lie21_prepare_blender.py
godot --path gpu_compute --editor --import --quit
godot --path gpu_compute res://lie21_human_lab.tscn
```

El exportador crea `captures/human_quality/` y un maestro editable
`assets/lie20/human-master-quality.blend`. Las capturas, buffers y maestro
generados se conservan como evidencia, no como blobs dentro de git.

## Reconstrucción y luz

La huella es una elipse que proyecta un disco tangente de la muestra y añade
una pequeña covarianza de reconstrucción. La profundidad se evalúa sobre el
plano geométrico. Una segunda fase combina color, normal detallada y rugosidad
con pesos gaussianos, aceptando solo muestras a menos de 0.65 mm de la
profundidad visible. Así se evita mezclar el lado opuesto de un pliegue.

La acumulación usa enteros de 32 bits, sin requerir atomics de float. Cada
contribución está acotada a 256: incluso el límite de un millón de muestras
en un solo píxel suma como máximo 256 millones. La cuantización es parte de
esta aproximación, no una representación de precisión ilimitada.

La sombra usa 512², huellas tangentes locales y nueve comparaciones.
La profundidad del receptor también se ajusta al rayo de cada comparación
PCF. Un plano inclinado aislado verifica en GPU que no aparece sombra propia.
La piel
difunde irradiancia separadamente del color, conservando el detalle de color
y el brillo especular. Sus radios RGB en metros se proyectan usando profundidad
y campo de visión. Sigue siendo difusión en pantalla, sin transporte
volumétrico completo ni espesor anatómico.

Ocho fases compute terminan con un resolve de cuatro subpíxeles en radiancia
lineal, seguido de exposición, Reinhard y sRGB. La salida guarda cobertura
fraccional en los bordes. La imagen GPU quieta se reutiliza; solo se actualiza
el paquete de cámara/pose/luz. Los controles y agentes usan el mismo documento
validado del taller humano. La alta calidad aumenta memoria y trabajo GPU.

## Comparación reproducible

El workflow ejecuta realmente LIE-20 y LIE-21 en el mismo dispositivo Vulkan
por software. Blender/Cycles dibuja el maestro original únicamente como
referencia independiente. Las cinco cámaras, poses, luz, texturas y tono
se mantienen fijos. Los errores RGB se calculan sobre una misma máscara
de primer plano común a las tres imágenes.

Criterios fijados antes de ejecutar la aceptación:

- Cada silueta nueva debe alcanzar IoU >= 0.98.
- El IoU medio debe mejorar al menos 0.007 frente a LIE-20.
- El error RGB medio debe reducirse al menos 5 % frente a LIE-20.

También se comparan 768 posiciones con la evaluación nativa del rig de Blender,
se comprueba cobertura fraccional real, mezcla de varias muestras, reutilización
estática, controles de usuario, comandos de agente y cambios efectivos de
dispersión/sombra. Los JSON informan memoria y tiempos de fases GPU en ambos
renderizadores; no son FPS del motor ni pruebas de Android.

## Límites

Mejorar estos criterios no demuestra equivalencia a Cycles ni hiperrealismo.
Persisten diferencias de iluminación indirecta, dispersión volumétrica,
oclusión, filtro de material y transporte especular. El escaneo tiene ojos
cerrados y carece de ojos completos, cabello e interior de boca. No hay
reconstrucción temporal deformable, LOD/streaming humano o medición física móvil.
Godot sigue aportando interfaz y dispositivo de renderizado.

Bases técnicas consultadas; el código implementa aproximaciones propias:

- Zwicker et al., Surface Splatting: https://www.merl.com/publications/TR2001-20
- Jimenez et al., Separable Subsurface Scattering: https://www.iryoku.com/separable-sss/
- Godot, Compositor: https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html
