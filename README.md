# Lie Engine — LIE-01 through LIE-21

**Research prototype, not a proven faster renderer.** Lie separates an invisible 3D world (physics and spatial transforms) from a camera-indexed image-based visual layer.

Lie is developed **on Godot 4.7.2**; its asset addressing and capture pipeline are kept independent of individual game projects. ARCONT can serve as an external testing/research laboratory, not as embedded game code.

## LIE-21 — human quality reconstruction

The human workshop now opens `gpu_compute/lie21_human_lab.tscn`: 36 neutral
384² captures, native Blender tangent frames, weighted elliptical material
reconstruction and a linear HDR 1024²-to-512² resolve. The invisible head/neck
rig and shared user/agent commands are retained. The dedicated workflow runs
the actual LIE-20 baseline and LIE-21 against fixed independent Blender/Cycles
references, reporting image error, silhouette, memory and software Vulkan cost.
See [LIE-21 protocol and limits](docs/LIE_21_HUMAN_QUALITY.md). This research
step does not claim Cycles equivalence, complete human realism or Android FPS.

## LIE-20 — captured human and invisible deformation

A locked, attributed Lee Perry-Smith scan becomes an editable Blender master
with a head/neck armature and experimental facial correctives. Thirty-six
neutral camera captures export grayscale, per-point RGB filters, detailed and
geometric normals, depth and stable surface bindings. Lie deforms and lights
the captured samples on the GPU; original triangles are never drawn. The
workshop opens a dedicated human inspector with shared user/agent commands,
skin diffusion controls, sample-based shadows and independent Blender camera
and pose references. Static portraits reuse their completed GPU image.

This is a human rendering research gate, **not achieved human hyperrealism**.
The scan has closed eyes; eyes, hair, mouth interiors, complete facial rigging,
human indirect transport and Android performance remain open work. Read
[setup, representation, evidence and limits](docs/LIE_20_HUMAN_MASTER.md).

## LIE-19 — reusable transport and live client

The workshop retains its reciprocal visibility graph when only lights, materials, bounce count or water codes change. Geometry edits still rebuild it. Input buffers upload only changed bytes; the factor matrix stays GPU-resident. Runtime measurement controls and a Python client expose the same running workshop to users and agents, with correlated replies and revision guards. Actual Vulkan acceptance compares cached transport with fresh recomputation and preserves matched pass timings. Read [LIE-19 controls and measurement limits](docs/LIE_19_TRANSPORT_CACHE.md).

## LIE-18 — assembly and animation workshop

Open `gpu_compute/project.godot` after preparing its two capture masters. Assemble, articulate, animate, relight and save a robot using reusable box/cylinder captures; visible controls and validated agent commands share one document. Blender remains the external authoring tool. Read [workshop setup and API](docs/LIE_18_WORKSHOP.md).

## LIE-17 — optional contrast-guided edges

An optional bounded contour filter is merged into final viewport composition, with per-tap native depth rejection and no extra intermediate image. The dedicated experiment uses analytic pixel-area oracles, thin-feature and occlusion cases, matched real motion frames and off/on/off consumer timings. Read [behavior, reproduction and limits](docs/LIE_17_CONTRAST_EDGES.md), or open `gpu_compute/lie17_lab.tscn` after preparing LIE-16 captures.

## LIE-16 — stable capture quality

The Arcont robot gains conservative capture mip levels selected by perceived size, projected sample footprints, per-piece/depth/normal view fusion, four-tap edge reconstruction and a temporal resolve that follows its invisible rigid skeleton. Current/previous owners and depth reject invalid history, while camera cuts and changed light/material codes reset it. No source meshes or generated intermediate frames are used. The dedicated experiment compares original-mesh geometry, static color variation, matched motion frames and consumer timestamps on software Vulkan.

Run `gpu_compute/lie16_lab.tscn` after preparing its bundle; read [controls, reproduction, validation and limits](docs/LIE_16_STABLE_QUALITY.md). Additional quality has a measurable cost; Android and physical-GPU performance remain unmeasured.

## LIE-14 — invisible articulation and perception masters

One fixed Blender cylinder is captured from 36 camera directions, with one neutral image, one normal map and one depth pass per view. Three rigid instances share the same immutable master buffer. An invisible joint hierarchy moves their perception bounds, collision cylinders, image samples and lighting nodes together. The camera-facing reconstruction preserves sample depth and perspective; the bounding box's faces are never displayed. Direct illumination now uses captured normals per pixel, while shrinking diffuse secondary sources remain node-based.

Open `gpu_compute/lie14_lab.tscn` after generating its bundle. Joint/orbit sliders and pose/light/absorption controls support direct interaction. The dedicated workflow compares GPU lighting with a float64 oracle, compares moving silhouettes/depth with independent analytic rays, and checks native depth and master reuse. Read [LIE-14 contract and reproduction](docs/LIE_14_RIGID_PERCEPTION_MASTERS.md). This first gate uses cylindrical masters and kinematic joints; it is not a general modeling editor or a measured mobile optimization.

## LIE-12 — actual Blender captures consume absorption-coded light

The LIE-10 image reprojection now has a consumer for LIE-11 spatial light codes. An offline capture associates every valid grayscale pixel with a stable XYZ surface node and a separate RGB material filter. Real source triangles serve as invisible light blockers. The complex LIE-10 object, floor and colored walls are rendered entirely from captured images, with moving point lights, colored secondary diffuse bounces and absorption controls. The old LIE-10 scene remains available as a regression baseline.

Generate the bundle and oracle with the commands in [LIE-12 integration and reproducibility](docs/LIE_12_CAPTURE_CODE_LIGHTING.md), then run `gpu_compute/lie12_lab.tscn`. The dedicated workflow checks actual GPU powers, independent-reference rendered frames, camera distance/orbit and native sprite depth ordering. Constant opaque Principled source colors and static geometry are the current exporter contract; large-scene performance, textured proxy averaging and transparent rain remain open work.

## LIE-11 — grayscale sprites and absorption-coded light transport

New independent Vulkan lighting laboratory: **the visible surfaces are grayscale Sprite3D images**, with XYZ/normal/area nodes and separate RGB material filters plus absorption codes. Point-light codes inject linear RGB power into nodes; bounded diffuse secondary sources transfer the remaining power to visible neighbors. GPU ping-pong generations preserve the energy budget. No source 3D mesh is drawn in this laboratory.

Run `python3 tools/lie_light_transport.py`, then open `gpu_compute/project.godot` and run `lie11_lab.tscn`. Arrows orbit the camera, WASD moves the light, B switches direct/two-bounce lighting, X changes red-wall absorption, O toggles a blocker, C changes the light color. The previous LIE-10 startup scene remains available. Read [physics, integration and limitations](docs/LIE_11_CODE_LIGHTING.md).

This module is a **coarse, opaque, diffuse RGB approximation**, tested against an independent float64 reference for the same graph. It does not yet replace LIE-10's Blender compositor lighting or implement per-pixel material masks, specular highlights, transmission or mobile performance validation.

## LIE-10 — complex geometry and GPU relighting (experimental)

A separate complex Blender-generated GLB is captured as albedo/depth/normals and rendered by Lie's global Vulkan compositor, with two directional light settings. The same original GLB is independently rendered by Godot for silhouette IoU and comparative frame-pacing statistics. The reported CI Vulkan **software driver** timing is not GPU performance evidence. Read [research protocol](docs/LIE_10_QUALITY_BENCH.md). Default startup scene in gpu_compute is `lie10_lab.tscn`. The original Godot project's startup lab remains LIE-06.

## LIE-09 — Blender captures, GPU normals and native depth (experimental)

The separate Godot `gpu_compute/` Forward+ project now starts `lie09_lab.tscn`. It loads four actual Blender-generated albedo/depth/normal views (not source triangles), reprojects samples in a GPU compute pipeline and compares Lie depth against a conventional Godot rasterized depth buffer. The automatic test puts a red native cube both in front of and behind the same Lie source. This requires generated `gpu_compute/captures/demo_shard` assets — see [LIE-09 instructions](docs/LIE_09_BLENDER_OCCLUSION.md). No claims of AAA visual quality or faster-than-raster performance.

## LIE-08 — GPU synthetic viewport laboratory (previous milestone)

The *separate* `gpu_compute/` Godot Forward+ project now has `lie08_lab.tscn` as its startup scene. Open that project in Godot 4.7.2 with Vulkan, press **Play** and use left/right arrows to orbit a procedural spherical source. The same global RenderingDevice computes four-view depth projection, z-buffer confidence fusion and an RGBA32F image, and a CompositorEffect displays it directly in the Godot viewport without a CPU image readback or 3D mesh reconstruction each frame. The sphere is a **mathematical fixture, not a Blender asset**.

LIE-08 adds screenshot CI validation at 0° and 35°, including a missing-pixel coverage check. The original project `project.godot` still starts the previous CPU LIE-06 lab and stays unchanged. Read [LIE-08 GPU viewport limitations](docs/LIE_08_VIEWPORT.md), especially the lack of Godot-native depth testing and mobile FPS evidence.

## LIE-06 — multi-view reference + real Vulkan GPU kernel (default in original project)

The startup scene `scenes/lie_06_lab.tscn` reconstructs a target-camera surface from **up to four nearest azimuth/elevation captures** with angular confidence. When per-pixel normal data is available, samples facing away from the current camera are rejected and grazing angles are attenuated. **Arrows** move the camera; **Space** reprojects on CPU.

A separate **`gpu_compute` Forward+ Vulkan project** runs an actual compute shader that fuses up to four **already projected candidates** per target pixel according to nearest depth, surface confidence and angular weight. This step is really executed on the GPU in CI; the complete projection step remains on CPU in the visible lab. Do not confuse the working GPU compute proof with a fully GPU-driven renderer.

A second Vulkan compute shader `gpu_compute/shaders/project_samples.glsl` performs **per-sample depth unprojection and projection into the current perspective camera**, checked numerically for centered, offset and clipped samples. Its output is not yet connected to the renderer's full screen-space scatter.

The `native/` directory contains a C++17 angular selector, compiled and verified by CTest. It is **not yet wired through GDExtension** into Godot. Production mobile speed, reliable continuous crossfade and silhouette improvements are still unproven; read [Lie 0.6 research gates](docs/LIE_06_RESEARCH.md).

## LIE-05 — target-camera depth reprojection (earlier lab)

The previous scene is `scenes/lie_reprojection_lab.tscn`: rotate the camera with **left/right**, then press **Space** to reconstruct the new view. Two captured angular images are unprojected into 3D, reprojected into the current perspective camera, and fused using a software nearest-depth test (world-space points, bounded 2×2 splats, depth-consistent albedo weighting). The output is a **real 3D surface reconstructed from images**, participating in Godot's ordinary Z-buffer. The original GLB geometry is never rendered in Lie mode.

The code is a deliberately **CPU-heavy research reference**, not a live mobile renderer. Frame-by-frame synthesis has not been made efficient. On a fresh checkout without Blender assets, the lab visibly uses a clearly labeled synthetic fixture rather than hiding an empty scene. Capture a real `assets/captures/demo_shard` bundle with the Blender 4.x command below, reopen/import in Godot, then the lab uses real depth captures. Read [LIE-05 protocol and limitations](docs/LIE_05_REPROJECTION.md).

## LIE-04 — angular coverage and visibility before reconstruction (older lab)

The older scene `scenes/lie_depth_lab.tscn` uses **two neighboring angular reconstructions** with complementary 4×4 Bayer screen masks. It gradually adjusts their coverage with camera azimuth while preserving Godot's normal Z-buffer. This is dithered coverage, NOT physically continuous view synthesis. Elevation remains nearest-sample.

Before loading textures or generating triangles, groups fully outside camera frustum or conclusively hidden by **authored opaque rectangular occluders** may be omitted. The occluder must correspond to a real fully opaque wall. See [LIE-04 technical contract](docs/LIE_04_VISIBILITY.md).

## LIE-03 — depth reconstructed visibility (earlier stage)

The startup `scenes/lie_depth_lab.tscn` loads **two overlapping Lie nodes**. Their visible triangles are reconstructed from the captured depth channels; the actual source glTF geometry remains absent from normal drawing. The usual Godot depth test now handles inter-node occlusion. Arrow keys orbit and Space changes the illumination tint. Geometry reconstruction is a CPU baseline, not yet an optimization.

See [LIE-03 research protocol](docs/LIE_03_DEPTH_OCCLUSION.md). Depth holes and memory-performance limitations remain unresolved.

## LIE-02: three-channel surfaces (older lab)

The older LIE-02 scene is `scenes/lie_surface_lab.tscn`: it displays a rigid camera-indexed sprite with **albedo + per-pixel normal + normalized depth**, an invisible physical collider, a bounded **parallax approximation**, and **single-source local diffuse lighting**. Arrows orbit the camera, **Space** switches warm/cool illumination. No per-pixel depth writeback, shadows, or real 3D scene reconstruction are claimed.

To generate real textures instead of synthetic fallback, use Blender 4.x:

```sh
blender --background --python tools/lie_capture_surface_blender.py -- \
  --input /absolute/source.glb --out assets/captures/demo_shard \
  --azimuth-steps 16 --elevations=-30,0,30 --resolution 512
python tools/validate_lie_surface.py assets/captures/demo_shard
```

Each angular code receives `.albedo.png`, `.normal.png` and `.depth.png`. Current capture supports opaque Principled glTF materials; check `docs/LIE_02_SURFACE.md` for constraints. CI creates a synthetic original GLB with Blender, captures all three channels, imports them into Godot, and records matched-camera Lie versus original-geometry images.

The previous LIE-01 lab is still available at `scenes/lie_lab.tscn`.

## Run

1. Install Godot 4.7.2 stable (Compatibility renderer).
2. Open `project.godot` and run the main scene.
3. LIE-06: arrows move the camera; **Space** rebuilds a four-source CPU reprojection. LIE-04 remains available from `scenes/lie_depth_lab.tscn`.
4. Observe the two source angular codes, number of triangles and CPU build time. The original source mesh is never drawn during Lie rendering. Earlier labs demonstrate independent invisible `StaticBody3D` collisions.

The placeholder deliberately is **not** a photographic asset. The first capability being tested is: **the same 3D object position deterministically retrieves one angular image at a time, without displaying a source 3D mesh.**

## Produce actual views with Blender

Requires Blender 4.x and a model in glTF/GLB format:

```sh
blender --background --python tools/lie_capture_blender.py -- \
  --input /absolute/path/to/model.glb \
  --out assets/captures/demo_shard \
  --azimuth-steps 16 --elevations=-30,0,30 --resolution 512
```

Reopen the Godot project to import the generated PNGs. Their stable paths are `assets/captures/demo_shard/az_00_el_00.png`, etc. The demo then loads these instead of placeholders, selecting the nearest angular view.

The older LIE-01 capture script writes **RGBA only**. The separate LIE-02 capture pipeline produces normal/depth images. Coherent PBR shadows, character animation, atlas batching and measured mobile performance are not implemented.

## Validation

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_view_index.gd
godot --headless --path . --script res://tests/test_invisible_proxy.gd
godot --headless --path . --quit-after 30
```

GitHub Actions checks angular selection, depth reconstruction, visibility rejection and multi-view GPU frames. Passing checks are NOT evidence of higher quality or Android FPS.

Read [architecture and research gates](docs/ARCHITECTURE.md).

## Licensing

The project is publicly readable. **No software distribution license has been selected yet**. Do not assume public availability permits redistribution of code. Independently sourced Blender assets retain their own licensing requirements.

LIE-13 adds material/energy-dependent secondary radii, thin glass and water
optical sprite codes, colored straight-segment light transmission and shared
opaque/transparent depth. Launch `gpu_compute/lie13_lab.tscn` explicitly.
[Contract, equations, controls and limits](docs/LIE_13_RADII_AND_DIELECTRICS.md).

## LIE-15 · Robot de Arcont

Un asset real de Kenney Factory Kit catalogado en Arcont se convierte en un maestro gris reutilizado por un robot de quince piezas. La cámara Lie reconstruye capturas con profundidad y normales, escala de perspectiva, luz dinámica y brillo GGX. El laboratorio incluye órbita, altura, acercamiento, animación e inspección 3D separada. Los rangos compactos y el descarte antes de iluminar se contrastan contra una imagen base idéntica.

Ver [contrato, controles, reproducción y límites](docs/LIE_15_ARCONT_ROBOT.md). Laboratorio: `gpu_compute/lie15_lab.tscn`; validación real: `.github/workflows/lie-15.yml`.

## LIE-18: taller de piezas y agentes

El proyecto GPU abre ahora un taller con biblioteca de maestros, piezas
reutilizables, jerarquía de articulaciones, claves, materiales, agua y lluvia.
Los controles y agentes comparten comandos JSON validados, transacciones,
revisión y deshacer/rehacer. Duplicar y animar conserva las capturas.

[Uso, preparación, API y límites](docs/LIE_18_WORKSHOP.md).
La primera versión incluye el bloque/chapa real de Arcont y un cilindro
original. Blender es una herramienta externa para preparar maestros.
El transporte de rebotes se reconstruye en GPU cuando cambia el montaje;
los fotogramas inactivos reutilizan el resultado.

## LIE-22: shared eye and destructible masonry masters

Open `gpu_compute/lie22_modular_lab.tscn` or the new workshop button after
preparing the neutral Blender library. The original meshes remain invisible.
See [LIE-22](docs/LIE_22_MODULAR_MASTERS.md) for shared user/agent controls,
local fracture, support connectivity, GPU budgets and limitations.
