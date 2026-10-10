"""Original cylinder master + the pinned Arcont plate/box. Captures are offline.

This makes editable .blend/.glb source files; it does not render visible meshes
in Lie. Cylinders use a conservative six-bin invisible box for transport and
collision, while captured normals and depth retain their round surface.
"""
from pathlib import Path
import json
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lie15_prepare_blender


def main():
    root = Path(__file__).resolve().parents[1] / 'gpu_compute/assets/workshop'
    root.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=.5, depth=1)
    obj = bpy.context.object
    obj.name = 'LieCylinderMaster'
    material = bpy.data.materials.new('LieNeutralGray')
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.65, .65, .65, 1)
    obj.data.materials.append(material)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    bpy.ops.wm.save_as_mainfile(filepath=str(root / 'cylinder.blend'))
    bpy.ops.export_scene.gltf(filepath=str(root / 'cylinder.glb'), export_format='GLB')
    triangles = []
    obj.data.calc_loop_triangles()
    for triangle in obj.data.loop_triangles:
        points = [obj.matrix_world @ obj.data.vertices[i].co for i in triangle.vertices]
        triangles.append([[p.x, p.z, -p.y] for p in points])
    (root / 'cylinder-triangles.json').write_text(json.dumps(triangles))
    print('LIE18 AUTHORING', len(triangles), 'cylinder triangles, source .blend + .glb')


if __name__ == '__main__':
    main()
