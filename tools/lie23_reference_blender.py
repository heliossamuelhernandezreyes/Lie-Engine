"""Independent native triangle renders, matched to the Lie frontal camera."""
from array import array
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie20_prepare_blender import blender
from lie20_reference_blender import configure_scene


def emission(name,color):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear()
    node=nodes.new('ShaderNodeEmission');node.inputs['Color'].default_value=(*color,1)
    out=nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(node.outputs[0],out.inputs['Surface'])
    return mat


def render_references(face,rig,eyes,root,pose):
    root=Path(root);root.mkdir(parents=True,exist_ok=True)
    camera=configure_scene();scene=bpy.context.scene;scene.cycles.samples=16
    target=Vector((0,.30,.02));camera.location=blender(target+Vector((0,0,.48)))
    camera.rotation_euler=(blender(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    original=list(face.data.materials)
    eye_original=[list(obj.data.materials) for obj in eyes]
    eye_colors=[(.8,.85,.9),(.035,.22,.42),(.001,.001,.001)]
    for obj in eyes:
        for index,material in enumerate(obj.data.materials):
            material=material.copy();obj.data.materials[index]=material
            material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*eye_colors[min(index,2)],1)
            material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.12
    eye_beauty=[list(obj.data.materials) for obj in eyes]
    albedo=[]
    for source in original:
        mat=source.copy();mat.name='ReferenceAlbedo_'+source.name
        bsdf=mat.node_tree.nodes.get('Principled BSDF')
        node=mat.node_tree.nodes.new('ShaderNodeEmission')
        if bsdf.inputs['Base Color'].is_linked:
            mat.node_tree.links.new(bsdf.inputs['Base Color'].links[0].from_socket,node.inputs['Color'])
        else:node.inputs['Color'].default_value=bsdf.inputs['Base Color'].default_value
        out=mat.node_tree.nodes.get('Material Output')
        mat.node_tree.links.new(node.outputs[0],out.inputs['Surface']);albedo.append(mat)
    white=emission('NativeEyeOwner',(1,1,1));black=emission('NativeLidOccluder',(0,0,0))
    mask=emission('NativeSilhouette',(1,1,1))
    counts={}
    for name,blink in [('open',0),('half-blink',.5),('closed',1)]:
        pose(face,rig,eyes,0,blink,0,0,.0017)
        for channel in ['beauty','albedo','eye-owner','mask']:
            mats=original if channel=='beauty' else albedo if channel=='albedo' else [black]*len(original) if channel=='eye-owner' else [mask]*len(original)
            for i,mat in enumerate(mats):face.data.materials[i]=mat
            for side,obj in enumerate(eyes):
                for i in range(len(obj.data.materials)):
                    obj.data.materials[i]=eye_beauty[side][i] if channel in ['beauty','albedo'] else white if channel=='eye-owner' else mask
            exr=root/f'native-{name}-{channel}.exr';scene.render.filepath=str(exr)
            scene.render.image_settings.file_format='OPEN_EXR';scene.render.image_settings.color_depth='32'
            bpy.ops.render.render(write_still=True)
            image=bpy.data.images.load(str(exr),check_existing=False);image.colorspace_settings.name='Non-Color'
            pixels=array('f',[0])*(512*512*4);image.pixels.foreach_get(pixels);bpy.data.images.remove(image)
            if channel=='eye-owner':counts[name]=sum(pixels[i]>.5 for i in range(0,len(pixels),4))
            if channel in ['beauty','albedo']:
                for i in range(0,len(pixels),4):
                    for c in range(3):
                        v=max(pixels[i+c]*1.4,0);v=v/(1+v)
                        pixels[i+c]=12.92*v if v<=.0031308 else 1.055*v**(1/2.4)-.055
            result=bpy.data.images.new('NativeReference',width=512,height=512,alpha=True,float_buffer=True)
            result.colorspace_settings.name='Non-Color';result.pixels.foreach_set(pixels)
            scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_depth='8'
            result.save_render(str(root/f'native-{name}-{channel}.png'),scene=scene)
            bpy.data.images.remove(result);exr.unlink()
    for i,mat in enumerate(original):face.data.materials[i]=mat
    for side,obj in enumerate(eyes):
        for i,mat in enumerate(eye_original[side]):obj.data.materials[i]=mat
    pose(face,rig,eyes,0,0,0,0,.0017)
    (root/'native-image-checks.json').write_text(json.dumps({'eye_owner_pixels':counts,'camera_target':list(target),'camera_distance':.48,'camera_fov':35,'renderer':'Blender Cycles native triangles','beauty_materials_matched':False},indent=2)+'\n')
    if counts['closed']!=0:
        raise ValueError('Native closed eyelids expose the eye: '+str(counts))


if __name__=='__main__':
    import sys
    from lie23_prepare_blender import build_face,prepare_native_eyes,native_pose
    face,rig,rest,weights,blink,arc,uvs,color,normal,spec,anchors,regions,removed=build_face()
    eyes=prepare_native_eyes(rig,anchors)
    folder=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else Path('/tmp/lie23-native-preview')
    render_references(face,rig,eyes,folder,native_pose)
