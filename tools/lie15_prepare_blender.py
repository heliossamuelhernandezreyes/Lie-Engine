"""Normalize the actual Arcont-catalogued Kenney master, preserving its detail.
Source mesh exists only in authoring / independent geometric reference.
"""
import base64, hashlib, json, sys
from pathlib import Path
import bpy
from mathutils import Vector
root=Path(__file__).resolve().parents[1]/'gpu_compute/assets/lie15'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
source=base64.b64decode((root/'box-small.glb.base64').read_text())
provenance=json.loads((root/'provenance.json').read_text())
if hashlib.sha256(source).hexdigest()!=provenance['source_glb_sha256']: raise ValueError('Source digest mismatch')
(root/'box-small.glb').write_bytes(source)
palette=base64.b64decode((root/'colormap.png.base64').read_text())
if hashlib.sha256(palette).hexdigest()!=provenance['source_palette_sha256']: raise ValueError('Palette digest mismatch')
(root/'Textures').mkdir(exist_ok=True)
(root/'Textures/colormap.png').write_bytes(palette)
bpy.ops.import_scene.gltf(filepath=str(root/'box-small.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
points=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
lo=Vector([min(p[k] for p in points) for k in range(3)]); hi=Vector([max(p[k] for p in points) for k in range(3)])
center=(lo+hi)/2; extent=hi-lo
triangles=[]
for o in meshes:
    matrix=o.matrix_world.copy()
    for v in o.data.vertices:
        p=matrix@v.co
        v.co=Vector([(p[k]-center[k])/extent[k] for k in range(3)])
    o.matrix_world.identity()
    o.data.calc_loop_triangles()
    for tri in o.data.loop_triangles:
        triangles.append([[float(o.data.vertices[i].co.x),float(o.data.vertices[i].co.z),float(-o.data.vertices[i].co.y)] for i in tri.vertices])
    for slot in o.material_slots:
        m=slot.material; nt=m.node_tree
        p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
        color=p.inputs['Base Color']; bw=nt.nodes.new('ShaderNodeRGBToBW'); combine=nt.nodes.new('ShaderNodeCombineRGB')
        if color.is_linked: nt.links.new(color.links[0].from_socket,bw.inputs['Color'])
        else: bw.inputs['Color'].default_value=color.default_value
        for c in ['R','G','B']: nt.links.new(bw.outputs['Val'],combine.inputs[c])
        nt.links.new(combine.outputs['Image'],color)
# Exporting glTF does not preserve arbitrary BW nodes: bake the palette image
# itself to grayscale; use the resulting simple supported glTF base color graph.
for image in list(bpy.data.images):
    if image.type!='IMAGE' or image.size[0]==0: continue
    pixels=list(image.pixels[:])
    for i in range(0,len(pixels),4):
        gray=.2126*pixels[i]+.7152*pixels[i+1]+.0722*pixels[i+2]
        pixels[i:i+3]=[gray]*3
    image.pixels[:]=pixels
    image.pack()
for o in meshes:
    for slot in o.material_slots:
        nt=slot.material.node_tree; p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
        tex=next((n for n in nt.nodes if n.type=='TEX_IMAGE'),None)
        if tex: nt.links.new(tex.outputs['Color'],p.inputs['Base Color'])
        else: p.inputs['Base Color'].default_value=(.7,.7,.7,1)
bpy.ops.export_scene.gltf(filepath=str(root/'master-neutral.glb'),export_format='GLB',export_animations=False)
(root/'source-triangles.json').write_text(json.dumps(triangles)+'\n')
print('LIE15 REAL KENNEY MASTER',len(triangles),'triangles; neutral palette; unit bounds')
