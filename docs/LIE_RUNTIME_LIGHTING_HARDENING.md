# LIE: transporte por radio e instancias que comparten el maestro

Esta continuación parte de WALL04 `7c12dcf`. El maestro escaneado y las
muestras de ladrillo y mortero conservan sus bytes originales. La pared sigue
teniendo una envolvente invisible, 96 identidades de ladrillo, 872 receptores
de luz y cero triángulos del maestro dibujados. Estas mejoras de ejecución
no certifican el realismo del mortero ni el rendimiento de un teléfono.

## Cambios implementados

| Parte | Comportamiento nuevo | Límite de la afirmación |
|---|---|---|
| Maestro de muestras | Un búfer inmutable compartido por SHA-256, stride y RenderingDevice; leases con liberación al último consumidor. | Integrado en `lie22_modular_effect` y sus derivados de construcción, no en los tres búferes personalizados de LIE27. |
| Vista e instancia | Proyección, profundidad, acumulación, salida, materiales y transporte siguen siendo privados de cada consumidor. | El banco compartido no equivale a una única salida para todas las cámaras. |
| Rebotes | CSR por receptor conserva los pesos float32 y el orden de fuentes, elimina exclusivamente ceros. | El grafo y la física aproximada de WALL04 permanecen iguales. |
| Escena inmóvil | No vuelve a resolver luz si sus entradas no cambiaron. Las actualizaciones de sombra invalidan el resultado. | La proyección visual todavía se ejecuta; esto no representa FPS totales. |
| Edición | Cambiar luz o material reutiliza el grafo; cambiar geometría lo reconstruye. Si crece CSR, solo se reemplaza el búfer de factores. | WALL04 rechaza geometría distinta de su grafo precomputado: exige un rebake con procedencia. |
| Radio | Modo opcional `irradiance`, umbral positivo y finito, decrecimiento y escalas de material. | `power` continúa siendo el valor predeterminado; no se cambió el aspecto con una nueva política automática. |
| Diagnóstico | Contadores de resoluciones, reutilización, bytes subidos, memoria exclusiva/compartida y timestamps identificados por efecto. | Las métricas del búfer no son RAM del proceso ni memoria total de Godot. |
| Regresión | Autoría histórica WALL01 de 6 nodos y WALL02 de 9 nodos en módulos distintos; dependencias instaladas antes de toda la suite. | Se conserva el SHA publicado de cada versión. |

El banco WALL04 tiene 61,767,760 bytes. Dos consumidores deben referenciar
una copia de esos bytes en GPU y conservar sus salidas independientes. El
banco CPU se comparte con PackedByteArray COW después de adquirir el lease;
su lectura y validación inicial pueden tener memoria transitoria adicional.

La matriz original tiene 872 × 872 pesos, 3,041,536 bytes y 2,618 aristas
distintas de cero. Su CSR ocupa 24,452 bytes: 99.1961% menos almacenamiento
de factores. Un rebote inspecciona 2,618 aristas, frente a 760,384 entradas
del bucle denso. Estos son conteos verificables, no una promesa de aceleración
de igual magnitud. El banco original y su SHA no se reemplazan: CSR se deriva
al restaurar los captures y se verifica contra su procedencia.

## Qué significa un radio de código físicamente

La luz real no se detiene en una esfera. El radio de código es una política
de truncamiento, coste y calidad. Absorción, filtro RGB y transmisión reducen
energía; la distancia reduce la irradiancia. Un límite espacial debe declarar
qué error acepta, además de cómo se contrae por generación.

Para un emisor difuso lambertiano representado por el centro de un parche,
su potencia saliente por canal P tiene intensidad máxima P/π. A distancia d,
la aproximación puntual cumple E ≤ P/(π d²), antes de obstrucción o
transmisión. El modo nuevo usa:

```
R_energía = sqrt(max(P_rgb) / (π * irradiance_cutoff))
R = min(R_padre * radius_decay, R_energía, radius_max) * radius_scale
```

`radius_scale` pertenece a [0,1]. La absorción ya está incluida en P; este
modo no vuelve a multiplicar la supervivencia de reflectancia. Las unidades
son potencia RGB relativa/m² mientras las entradas no estén calibradas.
La ley anterior procede de la aproximación difusa puntual, no de una solución
exacta de una superficie extensa a distancia cercana. Es una cota **por
emisor**: muchos emisores pequeños pueden sumar una contribución apreciable.
El radio máximo, el decrecimiento y la ventana suave también son decisiones
de calidad; conservan energía omitida como pérdida, no como luz redistribuida.

```json
"secondary_radii": {
  "mode": "irradiance",
  "radius_max": 6.0,
  "radius_decay": 0.82,
  "irradiance_cutoff": 0.001
}
```

Este bloque se acepta por el contrato del modelo existente. No introduce
un control remoto distinto ni se aplica sin selección del modo. El modo
histórico mantiene `power_reference`. Futuras políticas deberían asignar un
presupuesto de error agregado por receptor, medir los emisores descartados y
comparar con más generaciones, especialmente cerca de superficies grandes.

También quedan pendientes la calibración física de potencia, la iluminación
directa normalizada entre receptores, factores recíprocos entre áreas y una
BRDF especular/anisótropa. El transporte actual es una aproximación RGB
difusa; las láminas ópticas son transmisión en segmento recto, no trazado
completo de refracción. Los emisores fuera de cámara deben continuar en el
transporte: ocultar un visual no demuestra que su luz sea irrelevante.

## Investigación de hardware y de Godot

Las recomendaciones de Arm favorecen medir contención de atomics, accesos y
memoria antes de elegir trabajo. Se conserva el grupo de 64 hilos de
transporte y el de 8 × 8 de imagen; no se presupone un subgroup de 32 o 64.
CSR evita lecturas inútiles; compartir el banco evita una subida/copia por
consumidor; la caché evita despachar generaciones idénticas. Ninguna de estas
medidas requiere modificar el núcleo de Godot.

El coste de la reconstrucción todavía incluye proyección, atomics globales,
acumulación y cobertura. Un GPU móvil puede tratar compute y framebuffer de
forma muy diferente: no todos sus mecanismos de compresión se aplican a
storage images. Los siguientes experimentos útiles son reducción por tiles,
listas de candidatos por pantalla, culling conservador y comparación con
fragment/raster. Requieren el mismo banco, cámaras y gates de calidad.

No se cambian indiscriminadamente los acumuladores a FP16: guardan HDR y
pueden desbordarse antes del material y del tonemapping. Vulkan exige que el
formato declarado por el shader coincida con la imagen. Debe consultarse
soporte de uso/formato en RenderingDevice y comprobar saturación/error antes
de cualquier variante compacta.

Una modificación del código fuente de Godot tendría sentido si un perfil en
hardware real demuestra un coste que sus APIs no permiten evitar: gestión
de recursos/submit, sincronización de compositor, exposición de un formato
o capacidades ausentes. La evidencia presente no establece ese bloqueo.
El Poco conserva su baseline publicado; estas mejoras aún no tienen una
medición física nueva de FPS, temperatura, consumo o PSS.

Fuentes primarias consultadas el 2026-10-14:

- [PBRT: reflexión de superficie](https://pbr-book.org/4ed/Radiometry,_Spectra,_and_Color/Surface_Reflection)
- [PBRT: luces puntuales](https://pbr-book.org/4ed/Light_Sources/Point_Lights)
- [PBRT: reflexión difusa y ρ/π](https://pbr-book.org/4ed/Reflection_Models/Diffuse_Reflection)
- [Arm GPU Best Practices 2025](https://documentation-service.arm.com/static/67a62b17091bfc3e0a947695?token=)
- [Arm: compute, compresión y GPUs móviles](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/mali-and-unreal-engine-s-nanite-enabling-the-future-of-mobile-graphics)
- [Vulkan: storage images y formatos](https://docs.vulkan.org/guide/latest/storage_image_and_texel_buffers.html)
- [Godot 4.7: RenderingDevice](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html)

## Comprobación reproducible

Con Python, las dependencias de `requirements-ci.txt` y Godot 4.7.2:

```sh
python -m pip install -r requirements-ci.txt
python tools/lie_ci_prepare.py
python tools/lie_wall04_compose.py --restore
python tools/lie_light_transport.py
python tools/lie_runtime_reference.py
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path gpu_compute --editor --import --quit
godot --headless --path gpu_compute --script res://test_lie26_rig.gd
godot --headless --path gpu_compute --script res://workshop/test_lie_agent_session.gd
xvfb-run -a godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --audio-driver Dummy --script res://test_lie_runtime_transport.gd
xvfb-run -a godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --audio-driver Dummy --script res://test_lie_runtime_shared_samples.gd
```

El workflow `lie-runtime-hardening.yml` además abre una sesión desechable de
WALL04 y ejecuta el smoke, diagnóstico de cobertura y auditoría de huecos por
el `command()` validado. Conserva JSON, PNG reales y logs de errores. Compara
los gates publicados de WALL04, sin convertirlos en certificación visual.

Estado local inicial: 122 pruebas Python, una omitida por falta de su fuente
externa; 247 checks del rig y 20 de sesión de agente; importación y compilación
GDScript comprobadas. El entorno local
impide crear sockets de pantalla; la comprobación Vulkan se ejecuta en CI.
Los resultados nativos se registrarán antes de considerar validado el cambio.
