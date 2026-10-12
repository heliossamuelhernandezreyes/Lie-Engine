"""LIE-12: same complex LIE-10 asset, scaled into a diffuse bounce fixture."""
import runpy
import sys
from pathlib import Path
import bpy

output = Path(sys.argv[sys.argv.index("--")+1]).resolve()
runpy.run_path(str(Path(__file__).with_name("create_lie_complex_fixture_blender.py")), run_name="__main__")
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for obj in objects:
    obj.location *= .42
    obj.scale *= .42
    obj.location.z += .67

def surface(name, color, center, width, height, rotation):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*color, 1)
    # Custom property survives this offline source, export hook also recognizes names.
    mat["lie_absorption_code"] = 150 if "bounce red" in name else 200
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=5, y_subdivisions=5, size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rotation
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    obj.scale = (width/(max(xs)-min(xs)), height/(max(ys)-min(ys)), 1)
    obj.data.materials.append(mat)

surface("neutral receiver floor", (.8, .8, .8), (0, 0, 0), 2.6, 2.6, (0, 0, 0))
surface("bounce red wall", (.85, .025, .025), (-1.2, 0, .8), 2.6, 1.6, (0, 1.57079632679, 0))
surface("neutral receiver back", (.8, .8, .8), (0, 1.2, .8), 2.6, 1.6, (1.57079632679, 0, 0))
bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB")
print("LIE-12 COMPLEX BOUNCE SOURCE PASS", output.name)
