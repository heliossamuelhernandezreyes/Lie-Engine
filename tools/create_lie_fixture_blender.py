"""Generate original, asymmetric CC0-style procedural geometry for CI tests.
The fixture is synthetic and authored here, not downloaded from an external source.
"""
import sys
from pathlib import Path
import bpy

target = Path(sys.argv[sys.argv.index("--") + 1])
target.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

def block(name, center, scale, rgba):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.object
    o.name = name
    o.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    m = bpy.data.materials.new(name + "-paint")
    m.diffuse_color = rgba
    m.use_nodes = True
    node = m.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = rgba
    o.data.materials.append(m)

block("asymmetric-core", (0, 0, 0.2), (0.8, 1.0, 1.4), (0.6, 0.2, 0.1, 1))
block("right-fin", (0.62, 0, 0.4), (0.65, 0.28, 0.50), (0.1, 0.55, 0.70, 1))
block("upper-collar", (-0.2, 0, 1.05), (0.9, 0.8, 0.18), (0.9, 0.68, 0.15, 1))
bpy.ops.export_scene.gltf(filepath=str(target.resolve()), export_format="GLB")
print("LIE-02 FIXTURE GENERATED", target)
