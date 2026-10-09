"""LIE-10 original procedural *complex* glTF benchmark asset.
Deliberately NOT part of the captured rendering path: the GLB exists
solely for Blender capture and Godot raster reference comparison.
Geometry, source colors and geometry counts are reproducible in CI.
"""
import sys
from pathlib import Path
from math import pi, sin, cos
import bpy

if "--" not in sys.argv or len(sys.argv)<=sys.argv.index("--")+1:
    raise SystemExit("Usage: blender -b --python tools/create_lie_complex_fixture_blender.py -- OUTPUT.glb")
output=Path(sys.argv[sys.argv.index("--")+1])
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

def paint(name, rgba):
    material=bpy.data.materials.new(name)
    material.diffuse_color=rgba
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=rgba
    shader.inputs["Roughness"].default_value=0.74
    return material

steel=paint("blue alloy - captured albedo",(.13,.40,.74,1))
bronze=paint("brass rim - captured albedo",(.82,.49,.20,1))
ceramic=paint("pale ceramic - captured albedo",(.76,.78,.82,1))
red=paint("signal red - captured albedo",(.80,.18,.15,1))
teal=paint("teal inset - captured albedo",(.15,.65,.56,1))

def finish(name, material):
    mesh=bpy.context.object
    mesh.name=name
    mesh.data.materials.append(material)
    return mesh

def cube(name, pos, scale, material, spin=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
    obj=finish(name,material)
    obj.dimensions=scale
    obj.rotation_euler.z=spin
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return obj

def cylinder(name,pos,radius,depth,material,verts=24,spin=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=pos)
    obj=finish(name,material)
    obj.rotation_euler.z=spin
    return obj

cylinder("central faceted tower",(0,0,0),0.45,1.85,steel,64)
cylinder("upper cap ring",(0,0,.95),.67,.17,bronze,48)
cylinder("bottom mounting collar",(0,0,-.9),.66,.26,bronze,48)
cylinder("top antenna",(0,0,1.35),.12,.68,red,24)

# Cylindrical ribs and tilted panels. Opposing fins deliberately asymmetric.
for i in range(16):
    a=2*pi*i/16
    outer=0.60+(0.08 if i%3==0 else 0)
    panel_mat=teal if i%3==0 else ceramic if i%2 else steel
    cube("radial armor panel %02d"%i,
         (outer*cos(a),outer*sin(a),-.06+(i%4)*.10),
         (.14,.27,1.05-(i%3)*.13),panel_mat,a)
    if i%2==0:
        cylinder("edge pin %02d"%i,
                 (.90*cos(a),.90*sin(a),-.55+(i%3)*.16),
                 .07,.48,bronze,12)

# Detailed concentric gears: imported as real ~6000-triangle geometry.
for j,z in enumerate((-.52,.52)):
    bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=10,
                                    location=(0,0,z),major_radius=.85,
                                    minor_radius=.055)
    finish("machined torus %d"%j,bronze)
for i in range(12):
    a=2*pi*i/12+.07
    cube("gear teeth %02d"%i,
         (1.06*cos(a),1.06*sin(a),.52),
         (.25,.16,.19),red if i%4==0 else steel,a)

# Several partly hidden layers: deliberate disocclusion stress.
for i in range(8):
    a=2*pi*i/8+.12
    cylinder("inner pylon %02d"%i,
             (.30*cos(a),.30*sin(a),-1.10),.085,.68,
             ceramic if i%2 else teal,16)

objs=[o for o in bpy.context.scene.objects if o.type=="MESH"]
triangles=sum(len(poly.vertices)-2 for o in objs for poly in o.data.polygons)
assert len(objs)>=45 and triangles>2500,(len(objs),triangles)
bpy.ops.export_scene.gltf(filepath=str(output.resolve()),export_format="GLB")
print("LIE-10 COMPLEX GLB PASS meshes=%d triangles=%d"%(len(objs),triangles))
