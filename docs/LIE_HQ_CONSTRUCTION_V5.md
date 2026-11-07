# Construcción fotográfica v5 — 7 de noviembre de 2026

El banco añade **12 perfiles detallados** a los tres maestros de ladrillo
escaneado ya existentes. Permite componer una esquina trabada con abertura,
un marco con dintel/alféizar, una cubierta de tablillas y una puerta articulada.
El compositor reconstruye capturas; no dibuja las mallas fuente.

Las nuevas geometrías son de autoría del proyecto y usan fotografías PBR 8K.
**No son doce nuevos escaneos completos de objetos.** El ladrillo conserva el
escaneo original y las dos mitades derivadas; sus caras de corte son de autoría.
Los ocho prototipos históricos contenidos en el banco v3 no se han presentado
como nuevos materiales HQ ni se exponen como piezas del conjunto v5.

## Fuentes conservadas

| Material | Fuente y atribución | Uso |
| --- | --- | --- |
| Ladrillo | Centre-of-Archaeology, *Stratford New Place Brick Ver 2*, CC BY 4.0 | Original completo, mitad izquierda y derecha |
| Mortero | Poly Haven *Brick Wall 04*, Dimitrios Savva / Dario Barresi / Rico Cilliers, CC0 | Recortes de juntas reales; no caras de ladrillo |
| Concreto | Poly Haven *Concrete Layers*, Amal Kumar, CC0 | Dintel, alféizar y zócalo |
| Madera | Poly Haven *Wood Table Worn*, Dimitrios Savva / Rico Cilliers, CC0 | Perfiles de marco, vigas, hoja y tablillas |

Powered by Poly Haven. Los originales de madera y concreto ya entregados en
v4 se reutilizan byte por byte. La nueva fuente completa de mortero, sus mapas
y las regiones seleccionadas se conservan en el paquete de fuentes v5.

- Mortero: <https://polyhaven.com/a/brick_wall_04>
- Concreto: <https://polyhaven.com/a/concrete_layers>
- Madera: <https://polyhaven.com/a/wood_table_worn>
- Ladrillo: <https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a>

Las regiones de mortero están declaradas en píxeles del original 8192²:
`bed=[4300,632,5524,685]` y `head=[3790,105,3837,443]`. Los recortes tienen
1224×53 y 47×338 píxeles propios: que el archivo original sea 8K no convierte
cada recorte en una imagen independiente de 8K. Se conservaron el albedo,
rugosidad, desplazamiento, normal OpenGL y referencia de color originales.
Se verificó la codificación sRGB antes de decodificar a luz lineal.

Las dimensiones nominales publicadas por el proveedor se registran como tales.
La forma de los perfiles, los biseles, la concavidad, amplitud de relieve y UV
laterales/posteriores son de autoría. No constituyen metrología del objeto;
las UV de caras internas pueden estirar el recorte. El ladrillo antiguo conserva
colores de vértices originales; no se ha certificado la eliminación de toda
iluminación adquirida durante su escaneo.

## Maestros y conjuntos

Los doce maestros suman **6 022 600 triángulos fuente**. La complejidad fuente
no se sustituyó por primitivas de color plano; los triángulos son usados fuera
del tiempo de ejecución para capturar superficie, relieve y material.

| Maestro | Función |
| --- | --- |
| `mortar_bed` | Junta horizontal; también relleno interno explícitamente escalado |
| `mortar_head` | Junta vertical |
| `mortar_return` | Retorno de junta en L, dos cuerpos cerrados |
| `concrete_lintel` | Dintel |
| `concrete_sill` | Alféizar con pendiente |
| `concrete_plinth` | Zócalo/apoyo |
| `wood_head` | Travesaño del marco |
| `wood_jamb` | Jamba corta |
| `wood_door_jamb` | Jamba de puerta |
| `wood_beam` | Viga |
| `wood_door_leaf` | Hoja formada por cuatro tablas cerradas |
| `wood_shingle` | Tablilla de cubierta |

La esquina usa 18 hiladas y dos semillas reproducibles, 2102 y 7319. Cada una
contiene 198 ladrillos y 781 instancias totales. Los ladrillos mantienen escala
unidad, rotaciones propias, alternancia y pequeñas variaciones de tono. No se
reflejan ni estiran para cerrar la esquina. La separación del intercalado en la
esquina es 3.1441565 mm. La auditoría usa los límites reales de las mitades,
incluidos sus desplazamientos de centro en Y/Z, y no encuentra intersecciones
entre cajas conservadoras de ladrillos.

El relleno está retirado 15 mm en remates libres y bordes de aberturas para
no tapar los extremos irregulares del ladrillo. Dintel y alféizar ocupan sus
intervalos estructurales antes de generar las juntas. El hueco permanece vacío
por ambos lados. La cimentación tiene una intersección intencional entre sus
dos tramos: no se afirma que todos los cuerpos del conjunto sean disjuntos.

La cubierta usa **tablillas de madera**, no tejas cerámicas. Las vigas siguen
su pendiente y quedan bajo las tablas. La puerta gira rígidamente sobre el
anclaje izquierdo; no hay aún un asset fotográfico de bisagra metálica.
Tampoco se añadieron vidrio, transmisión, metal, manijas ni nuevos ladrillos
completos escaneados.

## Cambios del consumidor

Cinco bancos comparten una misma profundidad, propiedad, acumulación y mapa
de sombras. Se ejecutan las fases de proyección de todos los bancos y luego
la acumulación de todos, antes de sombrear y resolver una sola imagen.
La inversión del orden de bancos deja iguales profundidad y sombras y no
cambia RGB dentro de 1e-6.

El ABI de captura geométrica sigue siendo de 80 bytes por muestra. Un archivo
opcional separado de 16 bytes guarda la normal óptica y su validez, asociado
por SHA-256 al banco. Se obtiene mediante derivadas UV y marco tangente con
orientación de las UV. Afecta sólo al sombreado: la normal geométrica sigue
controlando visibilidad, huella, profundidad, límites y sombras. Activar o
retirar este canal cambia RGB y conserva exactamente los buffers geométricos.
No equivale a importar automáticamente toda extensión de material glTF.

Se añadió un índice de intervalos y límites fuente por banco. La huella y el
lanzamiento de sombras se restringen también al volumen del maestro. Así se
impide que planos tangentes de muestras de borde sobresalgan del perfil.
Es un límite AABB conservador, no una reconstrucción exacta de toda silueta
curva o cóncava. La dispersión de puntos aún puede perder detalle fino.

Los buffers inmutables geométricos y ópticos usan las concesiones compartidas
existentes. Una segunda instancia del consumidor hace cero subidas de assets;
el primer consumidor sigue funcionando después de liberar la segunda.
La memoria de trabajo de cada consumidor sigue siendo propia.

El sombreado nuevo usa GGX opaco no metálico, F0=.04 (IOR nominal 1.5 de
modelado, no medición del material). No añade transmisión ni compensación
completa de energía de normales de sombreado. Los consumidores históricos
mantienen sus valores anteriores.

## Verificación real y alcance de los resultados

- Python: 282 pruebas, 281 aprobadas y una omitida.
- Godot 4.7.2: rig, 247 comprobaciones; sesión de agente, 25.
- Vulkan real con Mesa llvmpipe LLVM 19.1.7: 49 comprobaciones del conjunto.
- Capturas individuales: 49 comprobaciones y 24 vistas, frente/reverso de
  los doce maestros nuevos.
- Comparación independiente: rayos contra triángulos fuente, UV y fotografías
  originales, con normal OpenGL y el mismo GGX/calibración; no usa puntos LIE
  ni llama al shader de reconstrucción como referencia.
- Tres maestros representativos también comparan LOD 1 y 2 con su captura
  densa: conservan más del 98 % de sus píxeles cubiertos. Los LOD más lejanos
  son derivados explícitos, no certificados para primeros planos.


| Maestro | Cobertura mínima | PSNR mínimo | RMSE máximo |
| --- | ---: | ---: | ---: |
| `mortar_bed` | 99.760 % | 31.60 dB | 0.205 mm |
| `mortar_head` | 99.801 % | 33.52 dB | 0.086 mm |
| `mortar_return` | 99.833 % | 32.85 dB | 0.097 mm |
| `concrete_lintel` | 99.799 % | 25.11 dB | 0.655 mm |
| `concrete_sill` | 99.781 % | 25.28 dB | 0.657 mm |
| `concrete_plinth` | 99.836 % | 25.17 dB | 1.341 mm |
| `wood_head` | 99.815 % | 29.89 dB | 0.440 mm |
| `wood_jamb` | 99.788 % | 29.91 dB | 0.346 mm |
| `wood_door_jamb` | 99.726 % | 29.09 dB | 1.246 mm |
| `wood_beam` | 99.754 % | 29.42 dB | 0.579 mm |
| `wood_door_leaf` | 99.837 % | 30.75 dB | 0.373 mm |
| `wood_shingle` | 99.793 % | 27.03 dB | 0.286 mm |

Las métricas por vista están en `evidence/source-comparison/comparison.json`.
Los límites de regresión son cobertura interior >=99.5 %, RMSE de profundidad
<2 mm y PSNR RGB >=23 dB. Se excluye un borde de cuatro píxeles para la métrica
interior. La referencia usa rayos centrales; el compositor resuelve 2×2
subpíxeles, diferencia que también contribuye al error. Es una aceptación
acotada de geometría/material, **no una certificación de hiperrealismo**.
Los primeros planos comparativos muestran la pérdida de microdetalle.

No hubo medición en Android físico ni comparación de FPS con la última APK.
No se produjo una APK nueva. llvmpipe valida el camino Vulkan y la corrección,
pero no representa velocidad ni consumo de una GPU móvil.

La escena del laboratorio carga los cinco bancos: **273 159 680 bytes** de
fuentes geométricas/ópticas. En la captura de esquina a salida 960² y trabajo
1920² se registran **453 680 304 bytes** exclusivos adicionales del consumidor.
La suma contable es 726 839 984 bytes (aprox. 693 MiB); no es una medición de
memoria total de proceso. Otros módulos probados después retienen esa capacidad
de trabajo. Compartir las fuentes no elimina esa memoria propia. No está
listo como presupuesto de teléfono de gama baja.

El campo indirecto compartido de `lie_light_world.gd` no se conectó a este
laboratorio. Las sombras comunes aquí verificadas no prueban integración del
campo, iluminación indirecta ni participación en profundidad/sombras nativas
de mallas Godot.

## Reproducir

Código y generadores están en `work/lie-hq-corner`. Los grandes bancos y
fotografías se distribuyen aparte. El banco v3 conserva SHA-256
`dbdf7b21727d4ee9c789dd8cdedde29c42297deae359e5089315b1a744160916`.

Con el paquete de banco descomprimido:

```bash
python -m pip install -r requirements-hq.txt
PYTHONPATH=tools python tools/lie_hq_construction_stage.py \
  --data /ruta/LIE_Banco_Construccion_v5/scene --output /tmp/lie-v5
Godot_v4.7.2-stable_linux.x86_64 --headless --path /tmp/lie-v5 --editor --import --quit
Godot_v4.7.2-stable_linux.x86_64 --path /tmp/lie-v5 \
  --rendering-driver vulkan --rendering-method mobile \
  --script res://test_lie_hq_construction.gd
Godot_v4.7.2-stable_linux.x86_64 --path /tmp/lie-v5 \
  --rendering-driver vulkan --rendering-method mobile \
  --script res://test_lie_hq_component_quality.gd
PYTHONPATH=tools python tools/lie_hq_construction_verify.py \
  --sources /ruta/fuentes/sources --stage /tmp/lie-v5 \
  --output /tmp/lie-v5-comparison --all-components
```

En un servidor sin pantalla se usa Xvfb para las dos ejecuciones Vulkan.
`external-materials.json` del ZIP de fuentes especifica los dos ZIP v4
reutilizados, sus IDs, prefijos internos y SHA de cada mapa. Restaurar esos
mapas en las carpetas de madera/concreto antes de recapturar o calcular la
referencia. No reemplazar los perfiles y descriptores v5 con los de v4.

La acción `lie-hq-construction.yml` adquiere fuentes fijadas por hash,
reconstruye maestros y bancos con procesos de captura separados, importa,
ejecuta las pruebas y sube evidencia. El banco de ladrillo se obtiene de un
artefacto histórico fijado por SHA; si caduca, debe usarse la copia conservada
con el mismo hash o reconstruirse explícitamente, nunca saltarse la validación.

## Fallos preservados y siguiente trabajo

Se rechazó un candidato de mortero con desplazamiento de 8 bits; no forma
parte del banco. Se corrigieron coordenadas duplicadas en las rejillas de
biseles, un límite de radio de captura que dejaba huecos, caras de corte
orientadas hacia el exterior y relleno que sobresalía en un remate. Una
captura acumulada de doce fuentes agotó memoria; ahora cada maestro se captura
en un proceso separado. Se retiró `OpArrayLength`, que el controlador de prueba
no soportaba, y se envía un conteo explícito. También se conservan evidencias
de fallos de arranque de pantalla y una ejecución de relleno interno más denso
interrumpida; ésta no es el conjunto final aceptado.

Antes de una casa completa, el siguiente bloque es residencia por demanda y
presupuesto de memoria de trabajo, conservar más microdetalle en primeros
planos y adaptar la propiedad de superficies de estos conjuntos al campo de
luz compartido. Después procede el ensayo en un teléfono real. Estos puntos
son limitaciones pendientes; no se contabilizan como mejoras ya terminadas.
