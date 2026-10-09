# LIE-12: coded light reaches actual captured Blender objects

The grayscale/material/light mechanism from LIE-11 now has an actual captured-image consumer in the LIE-10 reprojection pipeline. The original complex asset is scaled into a scene with a neutral floor, neutral back and red diffuse wall. All visible scene surfaces come from four Blender capture views; the source GLB is not loaded into the runtime scene. Original triangles are invisible spatial data for lighting visibility.

## Offline data contract

`--coded-lighting` is optional on the existing surface capture tool. Existing schema-2 exports and tests retain their previous behavior. The coded exporter currently accepts **constant opaque Principled base colors**; linked Base Color textures and unsupported material systems are rejected. It produces these additional files:

| File | Contents |
| --- | --- |
| `pixel-codes.bin` | 65,536 pairs of float32 vec4: neutral grayscale RGB + validity; separate linear RGB material filter + stable node ID |
| `sample-normal.bin` | Matching source UV/depth/validity and actual captured world normal, float32, little endian |
| `light-model.json` | Finite surface nodes, areas, material absorption codes, light codes, original triangle proxy and symmetric static visibility cache |
| `code-manifest.json` | Actual source camera bases, geometry metrics, mapping distances and counts |

For unlit linear RGB `c`, the exporter stores `gray=max(c)` and `filter=c/gray` (zero filter for zero gray). Their product reconstructs the source unlit color; grayscale itself has equal RGB channels. Absorption is independent metadata, not baked lighting. The display shader computes `gray * filter * (1-absorption) * E_node / pi`, followed by the same bounded display mapping used in LIE-11. There is no directional ambient substitute in the new consumer.

Offline surface clusters use a fixed 0.38 m grid, material identity and dominant normal direction. Areas and mean reflectance come from real source triangles, so overlapping capture views do not multiply the represented surface energy. Each cluster uses an actual triangle centroid as its representative position. Captured depth reconstructs XYZ; Blender BVH nearest-triangle lookup maps every valid source pixel to a stable cluster. Mapping is independent of the runtime camera. Multisample boundaries can mix two depths into a point between surfaces: pixels farther than 2% of the capture radius from any real triangle are invalidated, counted and excluded. The exporter fails if these discarded candidates exceed 5%; it does not silently assign fictitious surface points.

Normals are converted from Blender Z-up to Lie Y-up. The exporter uses actual captured camera matrices, including 20-degree elevation; the runtime no longer assumes equatorial source cameras for this consumer. The first coded contract is four 128-square views. All capture pixels retain their captured normal for reprojection confidence, while illumination is constant within each finite surface cluster.

## Shared lighting and composition

The generic LIE-11 module now also accepts an optional opaque triangle proxy. Point-light visibility runs two-sided open-segment triangle intersection in GPU compute. A static symmetric BVH visibility cache, generated offline from the same triangle positions, filters diffuse node-to-node transfer. The existing conservative area-reciprocal form factors and per-generation energy recurrence remain unchanged. Optional AABB blockers are still supported and combine with the mesh visibility cache.

The transport effect executes before opaque rendering; the captured-image consumer executes through the existing LIE-10 reprojection and LIE-09 native-depth composition. Both share the persistent GPU irradiance image and material buffer. Moving the light uploads only light codes. Changing absorption updates node material codes and regenerates transport; captured image/color data and node associations are retained. There is no normal runtime GPU readback. Geometry count changes require new transport allocations and regenerated offline visibility/mapping.

The new consumer inherits the LIE-10 implementation using two small overridable shader/uniform hooks; the older directional-light scene remains a regression baseline. The LIE-12 shader retains its five projection/depth/accumulation/resolve stages and adds code sampling in the material stage. Diffuse radiance is mapped for display before fixed-point color atomics, retaining the original rendering contract.

## Reproduction

```sh
blender --background --python tools/create_lie_coded_fixture_blender.py -- /tmp/lie12-source.glb
blender --background --python tools/lie_capture_surface_blender.py -- --input /tmp/lie12-source.glb --out gpu_compute/captures/coded_shard --azimuth-steps 4 --elevations=20 --resolution 128 --coded-lighting
python3 tools/lie_coded_reference.py gpu_compute/captures/coded_shard
python3 tools/lie_light_transport.py
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --editor --import --quit
godot --path gpu_compute --rendering-driver vulkan --rendering-method forward_plus --script res://test_lie12_capture_codes.gd
```

Run `lie12_lab.tscn` for interactive controls: arrows orbit, WASD moves the source, B toggles direct/two-bounce, X changes red-wall absorption, C changes source RGB, O turns light off. Runtime startup remains the older LIE-10 scene.

The dedicated workflow performs 20 Python tests and creates actual Blender images plus their coded bundle. An independent float64 solver tests direct source visibility against original triangles using a separate segment intersection implementation; both implementations share the authored static BVH pair-visibility cache. GPU node irradiance is checked for six scenarios. The actual captured-image frame is also compared with the same consumer supplied independent float64 irradiance. Camera perspective, orbit, zero light, colored secondary power reaching the neutral floor, and an ordinary sprite in front/behind captured geometry are tested. LIE-11 acceptance and all earlier engine regression workflows remain active.

## Practical limits

This is an opaque diffuse approximation using clustered finite surfaces and center quadrature, not an exact physical-scene solution. Material absorption/color and stable pixel/node association are functional; textured proxy reflectance integration, finer adaptive clustering, animated source geometry, sparse graphs and BVH GPU acceleration remain future work. Direct visibility currently scans up to 16,384 invisible triangles per node/light; dense bounce work is O(bounces*N^2). These are research budgets, not a scalable game-scene performance claim.

Four 128-square captures and the inherited 256-square reconstruction retain their existing disocclusion, sampling and silhouette limitations. Native depth is read for composition but captured depth is still not written into Godot's native depth buffer. Transparent particles/rain, refraction, Fresnel/specular response and combined depth consumers are therefore not completed by this change. CI uses software Vulkan and does not establish Android FPS or hardware GPU speedup.

## Primary references

- [Blender BVHTree API](https://docs.blender.org/api/current/mathutils.bvhtree.html): nearest-surface association and offline ray visibility.
- [Godot compositor integration](https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html) and [RenderingDevice](https://docs.godotengine.org/en/4.4/classes/class_renderingdevice.html): render-stage effects and persistent compute resources.
- [LIE-11 derivation and radiometry sources](LIE_11_CODE_LIGHTING.md): bounded diffuse transport, inverse-square source and absorption semantics.
