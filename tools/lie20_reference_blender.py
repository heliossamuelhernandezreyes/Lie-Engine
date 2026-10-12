"""Original triangles, native Blender armature and Cycles: independent images.

Camera and authored poses match the Lie test. Skin scattering, indirect light
and shadow filtering differ, so image differences are evidence, not a claim
that the renderers are physically equivalent.
"""
from array import array
import math
from pathlib import Path
import bpy
from mathutils import Vector


CASES=[('neutral',0,0,0,12,5,.85),('turned',25,0,0,12,5,.85),
       ('corrective',15,.7,.7,12,5,.85),('profile',-15,0,0,65,5,.85),('close',0,0,0,12,5,.62)]


def configure_scene():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
    scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
    scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.film_transparent=True
    scene.view_settings.view_transform='Raw';scene.render.image_settings.file_format='OPEN_EXR';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='32'
    world=bpy.data.worlds.new('ReferenceWorld');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.12,.14,.17,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.12;scene.world=world
    bpy.ops.object.camera_add();camera=bpy.context.object;camera.name='ReferenceCamera'
    camera.data.type='PERSP';camera.data.lens=36/(2*math.tan(math.radians(35)/2));camera.data.sensor_width=36;camera.data.sensor_fit='HORIZONTAL';camera.data.clip_start=.01;camera.data.clip_end=5;scene.camera=camera
    a=math.radians(-35);bpy.ops.object.light_add(type='POINT',location=(math.sin(a)*.42,-math.cos(a)*.42,.5))
    light=bpy.context.object;light.data.energy=5;light.data.color=(1,.87,.74);light.data.shadow_soft_size=0
    return camera


def render_references(obj,rig,root,pose):
    camera=configure_scene();scene=bpy.context.scene;original=obj.data.materials[0]
    mask=bpy.data.materials.new('ReferenceMask');mask.use_nodes=True
    nodes=mask.node_tree.nodes;nodes.clear();emission=nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=(1,1,1,1);emission.inputs['Strength'].default_value=1
    output=nodes.new('ShaderNodeOutputMaterial');mask.node_tree.links.new(emission.outputs['Emission'],output.inputs['Surface'])
    for name,head,lid,jaw,yaw,elevation,distance in CASES:
        pose(obj,rig,head,lid,jaw)
        y,e=math.radians(yaw),math.radians(elevation)
        target=Vector((0,0,.23));camera.location=target+Vector((math.sin(y)*math.cos(e),-math.cos(y)*math.cos(e),math.sin(e)))*distance
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        for channel,material in [('beauty',original),('mask',mask)]:
            obj.data.materials[0]=material
            scene.render.filepath=str(root/f'reference-{name}-{channel}.exr');bpy.ops.render.render(write_still=True)
            image=bpy.data.images.load(scene.render.filepath,check_existing=False);image.colorspace_settings.name='Non-Color'
            values=array('f',[0])*(512*512*4);image.pixels.foreach_get(values);bpy.data.images.remove(image)
            if channel=='beauty':
                for i in range(0,len(values),4):
                    for c in range(3):
                        value=max(values[i+c]*1.4,0);value=value/(1+value)
                        values[i+c]=value*12.92 if value<=.0031308 else 1.055*value**(1/2.4)-.055
            result=bpy.data.images.new(f'Reference {name} {channel}',width=512,height=512,alpha=True,float_buffer=True);result.colorspace_settings.name='Non-Color';result.pixels.foreach_set(values)
            scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_depth='8';result.save_render(str(root/f'reference-{name}-{channel}.png'),scene=scene);bpy.data.images.remove(result)
            scene.render.image_settings.file_format='OPEN_EXR';scene.render.image_settings.color_depth='32'
    obj.data.materials[0]=original;pose(obj,rig,0,0,0)
    print('LIE20 REFERENCES',len(CASES),'matched camera/pose pairs',flush=True)


if __name__=='__main__':
    import sys
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from lie20_prepare_blender import ROOT,pose
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'human-master.blend'))
    render_references(bpy.data.objects['LieHumanMaster_LeePerrySmith'],bpy.data.objects['LieInvisibleRig'],ROOT.parents[1]/'captures/human_master',pose)
