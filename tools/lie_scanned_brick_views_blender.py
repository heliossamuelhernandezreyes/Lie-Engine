"""Calibrated multiview RGB/depth/normal/material/triangle captures of the scan.

Uses Blender's original-triangle BVH; no shading is baked into captured RGB.
Original COLOR_0 may itself contain acquisition lighting: provenance says so.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time
import bpy
import numpy as np
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie22_prepare_blender import png


def srgb(a):
    return np.where(a<=.0031308,a*12.92,1.055*np.maximum(a,0)**(1/2.4)-.055)


def capture(root,resolution):
    source=np.load(root/'source-canonical.npz');vertices=source['vertices'];faces=source['triangles'];colors=source['colors']
    points=[Vector(p) for p in vertices];bvh=BVHTree.FromPolygons(points,faces.tolist(),all_triangles=True)
    span=float(np.ptp(vertices,axis=0).max())*1.12;views=[]
    directions=[(az,el) for el in (-60,0,60) for az in range(0,360,30)]+[(0,-90),(0,90)]
    rows,cols=np.mgrid[:resolution,:resolution];u=((cols.ravel()+.5)/resolution-.5)*span;v=(.5-(rows.ravel()+.5)/resolution)*span
    for number,(azimuth,elevation) in enumerate(directions):
        az,el=math.radians(azimuth),math.radians(elevation)
        direction=np.array([math.sin(az)*math.cos(el),math.sin(el),math.cos(az)*math.cos(el)])
        right=np.array([math.cos(az),0.,-math.sin(az)]);up=np.cross(direction,right);eye=direction*span*2
        origins=eye+u[:,None]*right+v[:,None]*up;ray=Vector(-direction)
        count=resolution*resolution;position=np.full((count,3),np.nan,dtype='<f4');normal=np.zeros((count,3),dtype='<f4');ids=np.full(count,0xffffffff,dtype='<u4');ray_distance=np.full(count,np.inf,dtype='<f4')
        for i,origin in enumerate(origins):
            hit,n,triangle,distance=bvh.ray_cast(Vector(origin),ray,span*4)
            if hit is not None:position[i]=hit;normal[i]=n;ids[i]=triangle;ray_distance[i]=distance
        mask=ids!=0xffffffff;selected=faces[ids[mask]];t=vertices[selected]
        e=t[:,1]-t[:,0];f=t[:,2]-t[:,0];q=position[mask]-t[:,0]
        ee=(e*e).sum(1);ff=(f*f).sum(1);ef=(e*f).sum(1);qe=(q*e).sum(1);qf=(q*f).sum(1);den=ee*ff-ef*ef
        b=(ff*qe-ef*qf)/den;c=(ee*qf-ef*qe)/den;weights=np.stack([1-b-c,b,c],axis=1)
        rgb=np.zeros((count,3),dtype='<f4');rgb[mask]=np.clip(np.einsum('ij,ijk->ik',weights,colors[selected]),0,1)
        depth=np.full(count,np.inf,dtype='<f4');depth[mask]=(position[mask]-eye)@(-direction)
        shape=(resolution,resolution);name='view-%02d'%number
        np.savez_compressed(root/(name+'.npz'),position_m=position.reshape(*shape,3),normal_world=normal.reshape(*shape,3),
                            color_linear=rgb.reshape(*shape,3),depth_m=depth.reshape(shape),ray_distance_m=ray_distance.reshape(shape),
                            triangle_id=ids.reshape(shape),mask=mask.reshape(shape),material_id=np.where(mask,0,65535).astype('<u2').reshape(shape),
                            roughness=np.float32(.6))
        rgba=np.concatenate([np.clip(np.rint(srgb(rgb)*255),0,255).astype(np.uint8),mask[:,None].astype(np.uint8)*255],axis=1)
        png(root/(name+'-color.png'),rgba.tobytes(),resolution)
        nrgba=np.concatenate([np.clip(np.rint((normal*.5+.5)*255),0,255).astype(np.uint8),mask[:,None].astype(np.uint8)*255],axis=1)
        png(root/(name+'-normal.png'),nrgba.tobytes(),resolution)
        pose=np.eye(4);pose[:3,:3]=np.stack([right,up,direction],axis=1);pose[:3,3]=eye
        views.append({'file':name+'.npz','azimuth':azimuth,'elevation':elevation,'width':resolution,'height':resolution,
                      'projection':'orthographic','span_m':span,'world_from_camera':pose.tolist(),'forward_world':(-direction).tolist(),
                      'pixel_origin':'top-left','pixel_centers':True,'valid_pixels':int(mask.sum()),
                      'sha256':hashlib.sha256((root/(name+'.npz')).read_bytes()).hexdigest()})
        print('SCANNED VIEW',number,azimuth,elevation,int(mask.sum()),flush=True)
    (root/'views.json').write_text(json.dumps({'schema':'lie-calibrated-scan-views/1','coordinate_frame':'meters, Y up, +Z front',
        'depth':'camera-forward distance from per-pixel orthographic ray origin; background is infinity',
        'unknown_positions':'NaN outside mask; never interpreted as geometry','normal':'geometric triangle normal, canonical world space',
        'color':'original linear glTF vertex COLOR_0 barycentric interpolation; PNG previews sRGB only',
        'material':'opaque nonmetal, original roughness factor .6; IOR 1.5 authored separately',
        'views':views},indent=2)+'\n')
    return vertices,faces,colors


def editable_and_preview(root,vertices,faces,colors):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mesh=bpy.data.meshes.new('Original scanned geometry');mesh.from_pydata(vertices.tolist(),[],faces.tolist());mesh.update()
    attribute=mesh.color_attributes.new(name='SourceColor',type='FLOAT_COLOR',domain='POINT')
    rgba=np.column_stack([colors,np.ones(len(colors))]).astype(np.float32);attribute.data.foreach_set('color',rgba.ravel())
    obj=bpy.data.objects.new('Scanned brick: original 500000 triangles',mesh);bpy.context.collection.objects.link(obj)
    material=bpy.data.materials.new('Original scan color and roughness');material.use_nodes=True
    bsdf=material.node_tree.nodes['Principled BSDF'];color=material.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='SourceColor'
    material.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color']);bsdf.inputs['Roughness'].default_value=.6;bsdf.inputs['Metallic'].default_value=0.
    mesh.materials.append(material)
    camera=bpy.data.objects.new('Reference camera',bpy.data.cameras.new('Reference camera'));bpy.context.collection.objects.link(camera)
    camera.location=(.34,.23,.42);direction=-camera.location;camera.rotation_euler=direction.to_track_quat('-Z','Y').to_euler();camera.data.lens=50
    light=bpy.data.objects.new('Inspection area light',bpy.data.lights.new('Inspection area light','AREA'));bpy.context.collection.objects.link(light)
    light.location=(-.15,.38,.32);light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler();light.data.energy=8;light.data.shape='DISK';light.data.size=.22
    scene=bpy.context.scene;scene.camera=camera;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=64;scene.cycles.use_denoising=False
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100;scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('Neutral inspection world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.15
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(root/'original-scan-reference.png');scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
    bpy.ops.render.render(write_still=True)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(root/'scanned-brick-source.blend'))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--capture',type=Path,required=True);p.add_argument('--resolution',type=int,default=384);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    if a.resolution not in (128,256,384,512):raise ValueError('Unsupported capture budget')
    root=a.capture.resolve();v,f,c=capture(root,a.resolution);editable_and_preview(root,v,f,c)
