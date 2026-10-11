"""Matched native assembled surfaces and pose oracles, separate from Lie."""
from array import array
import json
import math
import bpy
from mathutils import Vector
from lie20_prepare_blender import blender, lie, save_image
from lie20_reference_blender import configure_scene
from lie23_prepare_blender import native_pose, prepare_native_eyes
from lie23_reference_blender import emission


def render_references(face, rig, rest, triangles, variants, selected, modules, root, anchors, probes, blank):
    camera=configure_scene(); scene=bpy.context.scene;scene.cycles.samples=8
    eyes=prepare_native_eyes(rig,anchors)
    for obj in eyes:
        for i,mat in enumerate(obj.data.materials):
            mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*[(.8,.85,.9),(.035,.22,.42),(.001,.001,.001)][min(i,2)],1)
    blank_material=bpy.data.materials.new('BlankSkin');blank_material.use_nodes=True
    nodes,links=blank_material.node_tree.nodes,blank_material.node_tree.links
    node=nodes.new('ShaderNodeVertexColor');node.layer_name='BlankSkinColor'
    links.new(node.outputs['Color'],nodes['Principled BSDF'].inputs['Base Color'])
    nodes['Principled BSDF'].inputs['Roughness'].default_value=.50
    beauty=list(face.data.materials)+[blank_material];albedo=[]
    for mat in beauty:
        copy=mat.copy();copy.name='ModuleAlbedo_'+mat.name
        nodes,links=copy.node_tree.nodes,copy.node_tree.links
        bsdf=nodes.get('Principled BSDF');node=nodes.new('ShaderNodeEmission')
        if bsdf.inputs['Base Color'].is_linked:links.new(bsdf.inputs['Base Color'].links[0].from_socket,node.inputs['Color'])
        else:node.inputs['Color'].default_value=bsdf.inputs['Base Color'].default_value
        links.new(node.outputs[0],nodes.get('Material Output').inputs['Surface']);albedo.append(copy)
    mask=emission('ModuleSilhouette',(1,1,1))
    objects=[]
    for variant,coords in enumerate(variants):
        points=[p.copy() for p in blank['full_points']] if variant==0 else [p.copy() for p in rest]
        if variant!=0:
            for k,p in coords.items():points[k]=Vector(p)
        own_triangles=blank['full_triangles'] if variant==0 else triangles
        mesh=bpy.data.meshes.new('NativeAssembled_'+str(variant))
        mesh.from_pydata([blender(p) for p in points],[],own_triangles);mesh.update()
        layer=mesh.uv_layers.new(name='CaptureUV');source=face.data.uv_layers['CaptureUV']
        for poly in mesh.polygons:
            poly.use_smooth=True
            if variant==0 and poly.index>=len(blank['base_triangle_ids']):
                poly.material_index=2
                for loop in poly.loop_indices:
                    p=points[mesh.loops[loop].vertex_index];layer.data[loop].uv=(p.x,p.y)
            else:
                ti=blank['base_triangle_ids'][poly.index] if variant==0 else poly.index
                tri=face.data.loop_triangles[ti]
                poly.material_index=1 if ti in selected else face.data.polygons[tri.polygon_index].material_index
                for loop,old_loop in zip(poly.loop_indices,tri.loops):layer.data[loop].uv=source.data[old_loop].uv
        if variant==0:
            attribute=mesh.color_attributes.new(name='BlankSkinColor',type='FLOAT_COLOR',domain='POINT')
            for k,c in zip(blank['source_ids'],blank['colors']):attribute.data[k].color=(*c,1)
        for mat in beauty:mesh.materials.append(mat)
        obj=bpy.data.objects.new('NativeAssembled_'+str(variant),mesh);bpy.context.collection.objects.link(obj)
        obj.shape_key_add(name='Basis')
        for name in ['blink','blink_arc']:
            key=obj.shape_key_add(name=name);old=face.data.shape_keys.key_blocks[name];basis=face.data.shape_keys.key_blocks['Basis']
            for k,p in enumerate(points):key.data[k].co=blender(p)+(old.data[k].co-basis.data[k].co if k<len(rest) else Vector())
        for group in face.vertex_groups:
            new=obj.vertex_groups.new(name=group.name)
            for k in range(len(points)):
                if k>=len(rest):
                    if group.name=='Head':new.add([k],1.,'REPLACE')
                    continue
                try:value=group.weight(k)
                except RuntimeError:continue
                new.add([k],value,'REPLACE')
        modifier=obj.modifiers.new('NativeHeadRig','ARMATURE');modifier.object=rig
        obj.hide_render=True;obj.hide_set(True);objects.append(obj)
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH' and obj not in objects+eyes:obj.hide_render=True
    cases=[]
    for nose in range(4):
        for yaw in [0,45,90]:cases.append({'nose_index':nose,'camera_yaw':yaw,'head_yaw':0,'blink':0,'render':True})
    cases += [{'nose_index':1,'camera_yaw':-90,'head_yaw':0,'blink':0,'render':True},
        {'nose_index':2,'camera_yaw':45,'head_yaw':20,'blink':1,'render':False}]
    target=Vector((0,.30,.02))
    for index,case in enumerate(cases):
        for obj in objects:obj.hide_render=True
        obj=objects[case['nose_index']];obj.hide_render=False
        native_pose(obj,rig,eyes,case['head_yaw'],case['blink'],0,0,.0017)
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
        positions=[lie(evaluated.matrix_world@v.co) for v in mesh.vertices]
        active=[p for p in probes if p['group'] in [0,case['nose_index']+1]]
        case['probes']=[{'sample':p['sample'],'position':list(sum((positions[k]*w for k,w in zip(p['triangle'],p['bary'])),Vector()))} for p in active]
        evaluated.to_mesh_clear()
        code=f"nose-{case['nose_index']}-yaw-{case['camera_yaw']}"
        case['code']=code
        if not case['render']:continue
        yaw=math.radians(case['camera_yaw']);camera.location=blender(target+Vector((math.sin(yaw)*.48,0,math.cos(yaw)*.48)))
        camera.rotation_euler=(blender(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        for channel in ['beauty','albedo','mask']:
            for i in range(len(beauty)):obj.data.materials[i]=beauty[i] if channel=='beauty' else albedo[i] if channel=='albedo' else mask
            eye_materials=[list(e.data.materials) for e in eyes]
            if channel=='mask':
                for e in eyes:
                    for i in range(len(e.data.materials)):e.data.materials[i]=mask
            exr=root/f'native-{code}-{channel}.exr';scene.render.filepath=str(exr)
            scene.render.image_settings.file_format='OPEN_EXR';scene.render.image_settings.color_depth='32'
            bpy.ops.render.render(write_still=True)
            image=bpy.data.images.load(str(exr),check_existing=False);image.colorspace_settings.name='Non-Color'
            pixels=array('f',[0])*(512*512*4);image.pixels.foreach_get(pixels);bpy.data.images.remove(image);exr.unlink()
            if channel!='mask':
                for i in range(0,len(pixels),4):
                    for c in range(3):
                        v=max(pixels[i+c]*1.4,0);v=v/(1+v);pixels[i+c]=12.92*v if v<=.0031308 else 1.055*v**(1/2.4)-.055
            scene.render.image_settings.file_format='PNG'
            save_image(root/f'native-{code}-{channel}.png',pixels,512,8)
            for e,mats in zip(eyes,eye_materials):
                for i,mat in enumerate(mats):e.data.materials[i]=mat
        for i,mat in enumerate(beauty):obj.data.materials[i]=mat
    for obj in objects:obj.hide_render=True;obj.hide_set(True)
    objects[1].hide_render=False;objects[1].hide_set(False)
    native_pose(objects[1],rig,eyes,0,0,0,0,.0017)
    (root/'native-oracle.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
