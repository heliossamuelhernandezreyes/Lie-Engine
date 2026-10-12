"""One smooth cylinder master, fixed in space; no lights baked into sprites."""
import math
import sys
from pathlib import Path
import bpy

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=.18, depth=1.2)
obj = bpy.context.object
obj.name = "Lie rigid cylinder master"
for gray in [.8, .48]:
    material = bpy.data.materials.new("Neutral master %.2f" % gray)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (gray, gray, gray, 1)
    obj.data.materials.append(material)
for polygon in obj.data.polygons:
    polygon.use_smooth = abs(polygon.normal.z) < .5
    angle = math.atan2(polygon.center.y, polygon.center.x)
    polygon.material_index = 1 if -.4 < angle < .1 and abs(polygon.normal.z) < .5 else 0
destination = Path(sys.argv[sys.argv.index("--")+1]).resolve()
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", use_selection=False)
print("LIE-14 MASTER SOURCE", destination)
