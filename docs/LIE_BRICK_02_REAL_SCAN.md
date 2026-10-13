# LIE-BRICK-02 — fuente geométrica completa, textura original y una sola caja invisible

## Estado real (no confundir fixture con fotogrametría)

Esta rama añade **un importador ejecutable** para `GLB`, `glTF` y `OBJ` autorizados, un nuevo laboratorio Godot y pruebas de GPU. Las pruebas automáticas **usan un GLB sintético deformado y texturizado**, claramente identificado. Eso valida la tubería, NO significa que hayamos descargado el escaneo de Shakespeare ni alcanzado fotorrealismo.

La **fuente externa de alta resolución identificada** para un ladrillo completo es:

- [Stratford New Place Brick Ver 2](https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-6077f6801089403993f6a6612ff5739a), Centre of Archaeology.
- Ficha pública: 500,000 triángulos, 250,000 vértices, ladrillo completo de 8 × 3¾ × 2 pulgadas, Creative Commons Attribution 4.0 (CC BY 4.0).
- El usuario o agente autorizado debe utilizar la **descarga normal** de Sketchfab e iniciar sesión cuando se requiera; el código no intenta eludir autenticación. Archivos con bloqueos de descarga NO deben obtenerse mediante endpoints de visor, scraping o técnicas de evasión.
- La licencia CC BY **no es CC0**: conservar autor, URL, licencia y procedencia en exportaciones/obras derivadas.
- El proyecto de procedencia [Searching for Shakespeare](https://searchingforshakespeare.co.uk/new-place/) especifica **escáneres 3D de luz estructurada**, no fotogrametría. El importador por sí mismo solo prueba que el archivo tiene geometría 3D y una textura UV real; no certifica la técnica de escaneo ni la autoría.

## Qué está implementado

- `tools/lie_brick02_capture_scan.py`: acepta un `.glb`, `.gltf` o `.obj` **ya obtenido legítimamente y descomprimido**. Lee geometría, transformaciones de escenas, triángulos, UV y texturas; samplea triángulos por área a posiciones **XYZ originales** y escribe registros LIE de **80 bytes/muestra** (posición, normales, color lineal, rugosidad, soporte).
- Tres LOD por defecto (220K / 52K / 9K muestras); semilla fija y SHA-256 de fuente y banco. La fuente no se dibuja como triángulos en LIE.
- `gpu_compute/lie_brick02_scan_lab.tscn`: laboratorio Vulkan de 1080×1080 con un `BoxShape3D` invisible derivado de los límites reales **con margen de 3 mm**. El master visual no está limitado por caras de la caja.
- `tools/lie_brick02_fixture.py`: genera un ladrillo GLB geométrico **falso y determinista** para pruebas de compatibilidad.
- `tools/lie_brick02_native_smoke.py`: prueba real Godot/Vulkan con 3 ángulos, un collider y conmutación LOD; cualquier PNG generado desde el fixture debe rotularse **SYNTHETIC NOT PHOTOGRAMMETRY**.

### Criterios y límites

El archivo fuente debe poseer triángulos no degenerados, ocupar volumen y tener UV y una textura real. La carga falla si faltan o se detecta un bloque aplanado. Las fuentes Draco podrían requerir convertir mediante Blender/DracoPy a un GLB estándar manteniendo la geometría y textura originales; esta herramienta no hace una conversión silenciosa.

La escala física **no es una dimensión que descubra LIE**: se asigna con `--length-m`. Para el ejemplo histórico: 8 pulgadas = **0.2032 m** de longitud; las otras dimensiones conservan las proporciones geométricas del escaneo original.

Los samples no son un fotorealismo garantizado: la cobertura de puntos, la continuidad de silueta, las normales, las sombras y las referencias de color deben medirse con fotografías del mismo objeto. `hero_quality_accepted` y `photo_reference_ab_test_passed` permanecen `false`.

## Cómo capturar un scan autorizado

```bash
python -m pip install numpy pillow trimesh
# 1. Descarga el modelo mediante Sketchfab de forma autorizada; descomprímelo.
# 2. Comprueba que el GLB/GLTF/OBJ y sus mapas son completos.
# 3. Copia y edita la procedencia de docs/assets:
cp docs/LIE_BRICK02_PROVENANCE_EXAMPLE.json /tmp/my_brick_provenance.json
# 4. Opcionalmente introduce el SHA256 esperado del archivo original.
python tools/lie_brick02_capture_scan.py \
  --source /ruta/legitima/brick.glb \
  --provenance /tmp/my_brick_provenance.json \
  --output gpu_compute/captures/liebrick02 \
  --length-m 0.2032
godot --headless --path gpu_compute --editor --import --quit
python tools/lie_agent_launch.py --godot /ruta/a/godot --lab liebrick02 \
  --directory /tmp/liebrick02-inspection
```

La carga de muestras es **independiente de la caja de colisión**, de modo que un futuro `LieWallCluster` puede compartir un master entre ladrillos, con un envelope para el grupo y envelopes hijos si se destruye o selecciona cada ladrillo. Este commit no implementa todavía la compactación visual de pared a un draw ni la colisión fina.

## Verificación sin fuente privada

```bash
python tools/lie_brick02_fixture.py --directory /tmp/liebrick02-fixture
python tools/lie_brick02_capture_scan.py \
 --source /tmp/liebrick02-fixture/SYNTHETIC_NOT_PHOTOGRAMMETRY.glb \
 --provenance /tmp/liebrick02-fixture/provenance.json \
 --output gpu_compute/captures/liebrick02
python -m unittest discover -s tests -p 'test_lie_brick02_capture.py' -v
```

La [acción LIE-BRICK02](../.github/workflows/lie-brick02-scanned.yml) ejecuta estas pruebas y, en CI, comprueba el compositor Vulkan en mesa llvmpipe. Ese resultado no sustituye mediciones en GPU Android o AMD/NVIDIA.

## Aceptación visual pendiente

1. Conseguir legítimamente un escaneo original íntegro del ladrillo, con mapa de color multivista.
2. Registrar los hashes del archivo y procedencia de artista (y si hubo conversión para quitar Draco, hashes antes/después).
3. Ejecutar un A/B con fotos del **mismo objeto** a igual ángulo, distancia e iluminación, cuantificar error de silueta, pérdida de detalles, agujeros, reflejos y borde de canto.
4. Medir coste de CPU/GPU y VRAM en dispositivo real, contrastar con LIE-BRICK-01 y geometría rasterizada original.
