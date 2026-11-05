# LIE 2.5 — auditoría real de banco → campo capturado → fotograma Vulkan

**Fecha de preparación: 2026-11-05. Estado: prueba de ejecución y recolección incorporada a CI; no se adjudica un resultado hasta que GitHub Actions termine exitosamente.** No se ha modificado `main` ni el renderizador de producción.

## Pregunta

En la cámara del teléfono que produjo ladrillos deformados (yaw -72.90939846038818°, elevación 2.0563994513617607°, distancia 0.6, 720²), ¿qué proporción de fallos aparece al convertir las **muestras de superficie reales de WALL06** en celdas capturadas, y qué proporción aparece después, durante su consulta y renderizado?

Se distinguen tres objetos diferentes que no deben mezclarse:

1. **Malla original escaneada de Stratford**: 500,000 triángulos de la fuente CC BY 4.0 y SHA-256 `b55b9d584fcfa6d7baf9e1d815c02578d91e092efc4cf88a47c23bbee643031b`. Es **referencia externa**, no va incluida en el runtime ni se reconstruye mágicamente a partir del banco. Esta etapa **no la ha contrastado**.
2. **Banco fuente de LIE-WALL06**: 41,700,560 bytes, SHA-256 `ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340`. Contiene muestras originales y mortero fotografiado con XYZ/normal/radio/color/identidad y pose/atribuciones; sirve de **fuente para la compilación del campo de celdas**.
3. **Campo de celdas finitas de cuatro capas**: compilado por `lie_direct_surface.py` a partir del banco fuente. Lo consulta el algoritmo de `lie_native_oracle.py` y, por separado, el compositor Vulkan con native-depth.

Por tanto el informe de esta etapa prueba el trayecto **banco de muestras → celdas → GPU**, **NO** la equivalencia total **malla original → muestras**. Para un dictamen completo falta contrastar la fuente GLB y la malla del mortero en una auditoría offline separada.

## Código real y control de identidad

- [Herramienta](../tools/lie_wall25_sufficiency.py): carga el banco bloqueado, selecciona los 220,000 registros de ladrillo de alta densidad y el nivel de mortero que usa el compilador; mantiene transformaciones/proxies y matrices capturadas de la GPU; busca el impacto visible sobre discos finitos de la fuente; contrasta con oráculo float64 de celdas y con readback real de Vulkan.
- [Pruebas de lógica](../tests/test_lie_wall25_sufficiency.py): trazado del disco más próximo, huecos, reverso, poda espacial, datos del proxy, clasificación y selección determinista.
- [Workflow de GitHub](../.github/workflows/lie-wall25-sufficiency.yml): restaura el mismo banco atribuido y lo comprueba por SHA; compila campo/paquetes, ejecuta el test nativo a la cámara exacta y preserva un JSON con diferencias de cobertura, profundidad y propietarios.

**Separación de evidencia:** las imágenes PNG no bastan para inferir propietarios. El JSON usa archivos binarios de `surface_world`, paquetes de vistas/proxies y el atlas de celdas original. El trazado de discos y el trazado de celdas usan métodos distintos: KDTree solo reduce candidatos de discos y el oráculo de celdas recorre los límites del campo capturado. La GPU es la tercera implementación.

## Cómo interpretar el JSON

- `source_bank_to_field`: diferencias reales entre la representación de discos capturados y la representación de celdas, en los rayos elegidos. Diferencias de cobertura/propietario/profundidad son cambios de representación que hay que investigar; no son por sí solas errores contra el GLB original.
- `field_to_native_gpu`: errores al consultar la representación de celdas. Un campo correcto con un resultado GPU incorrecto indica defecto del método de consulta, de precisión o de selección.
- `bank_to_native_gpu`: efecto total entre el banco y la salida.
- `regions_to_field_reference_only`: comprobación comparativa, **regions no es la verdad de fuente**.

Se muestrean de forma determinista hasta 128 discrepancias de propietario/cobertura entre regions y native, además de 96 rayos en áreas cubiertas y 48 rayos de fondo. No es una muestra aleatoria uniforme de la pantalla, y **no es una estimación de porcentaje global de error**. Se conservan hasta 150 ejemplos con coordenada de píxel, profundidad e identidad de cada nivel.

Se usa tolerancia diagnóstica de 1 mm para comparar discos y celdas (representaciones físicamente diferentes), y 20 μm para celdas y GPU (misma representación), sin confundir esas tolerancias con un requisito universal de LIE. El chequeo numérico exige que ambas referencias encuentren impacto, sin afirmar igualdad perfecta.

## Reproducción por GitHub Actions

El trabajo dirigido es `LIE 2.5 source bank / cell field / Vulkan sufficiency`. Sus artefactos contienen `lie-wall25-three-stage.json`, logs, `execution.json` e imágenes sin cambios del backend, si la ejecución llega a ese punto.

Para reproducir con un checkout que contenga los activos restaurables y Godot 4.7.2:

~~~bash
python -m pip install -r requirements-ci.txt
python -m unittest discover -s tests -p 'test_lie_wall25_sufficiency.py' -v
python tools/lie_direct_access_shaders.py
python tools/lie_direct_views_shaders.py
python tools/lie_native_shaders.py
python tools/lie_direct_views_build.py --stage /tmp/lie-wall25-source-stage
python tools/lie_native_stage.py --stage /tmp/lie-wall25-source-qa
godot --headless --path /tmp/lie-wall25-source-qa --editor --import --quit
xvfb-run -a godot --path /tmp/lie-wall25-source-qa --rendering-driver vulkan --rendering-method mobile --script res://test_lie_native_depth.gd
python tools/lie_wall25_sufficiency.py --bank gpu_compute/captures/liewall06 --captures /tmp/lie-wall25-source-qa/native-depth --output /tmp/lie-wall25-three-stage.json
~~~

**Estado de aceptación:** no aceptar un cambio de arquitectura solo porque se encuentre una disparidad banco/celda. Debemos comparar después el banco con el **GLB verificado** y los resultados de iluminación por separado; un detalle de la malla fuente puede no existir en las muestras aunque el campo reproduzca fielmente las muestras.
