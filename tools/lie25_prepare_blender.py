"""Capture a cropped 3DAnatomyman bust by layer, without baked light.

Run in Blender with auto-execution disabled. The source is acquired separately;
this tool never contacts Gumroad or stores purchase credentials.
"""
import argparse
import gc
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

LAYERS = ['Skin / Hair', 'Muscle', 'Skeleton', 'Internal']
SOURCE_SHA = 'a47d7ea9ae4082b793d4d45761c4c73db96707bb5f03c279b4133053c6c3e193'
PALETTE = [[.52,.29,.18,.55],[.32,.045,.028,.48],[.72,.64,.47,.65],[.29,.12,.15,.58]]
FOOTPRINT = [.45,.45,.38,.40]


def bound_height(obj):
    # Imported local axes differ from Blender's Z-up world orientation.
    return max((obj.matrix_world @ Vector(p)).z for p in obj.bound_box)


def layer_mesh(layer, bottom):
    points, triangles, names = [], [], []
    for obj in list(bpy.data.collections[layer].objects):
        if obj.type != 'MESH' or bound_height(obj) < bottom:
            continue
        if 'hair' in obj.name or 'eyebrow' in obj.name:
            continue
        mesh = obj.data
        coords = np.empty(len(mesh.vertices)*3, dtype=np.float32)
        mesh.vertices.foreach_get('co', coords)
        coords = coords.reshape(-1,3)
        matrix = np.asarray(obj.matrix_world, dtype=np.float64)
        coords = coords @ matrix[:3,:3].T + matrix[:3,3]
        coords = coords[:,[0,2,1]]*np.array([1.,1.,-1.])  # Lie Y-up
        # Avoid caching loop triangles for the complete 26 M polygon body.
        loop_ids = np.empty(len(mesh.loops),dtype=np.int32)
        mesh.loops.foreach_get('vertex_index',loop_ids)
        starts = np.empty(len(mesh.polygons),dtype=np.int32)
        totals = np.empty(len(mesh.polygons),dtype=np.int32)
        mesh.polygons.foreach_get('loop_start',starts)
        mesh.polygons.foreach_get('loop_total',totals)
        selected = np.minimum.reduceat(coords[loop_ids,1],starts)>=bottom
        starts,totals = starts[selected],totals[selected]
        faces = np.concatenate([np.stack([loop_ids[starts[totals>k]],loop_ids[starts[totals>k]+k-1],loop_ids[starts[totals>k]+k]],axis=1) for k in range(2,int(totals.max()))]) if len(totals) else np.empty((0,3),dtype=np.int32)
        if not len(faces):
            continue
        ids = np.unique(faces)
        remap = np.full(len(coords),-1,dtype=np.int32)
        remap[ids] = np.arange(len(ids)) + len(points)
        points.extend(coords[ids].tolist())
        triangles.extend(remap[faces].tolist())
        names.append(obj.name)
        print('EXTRACT',layer,obj.name,len(faces),flush=True)
    if not triangles:
        raise ValueError('Empty anatomical layer: '+layer)
    return points, triangles, names


def save_npz(path, **arrays):
    # Publish only closed archives, so readers never see an unfinished ZIP.
    temporary = path.with_suffix('.pending.npz')
    np.savez_compressed(temporary, **arrays)
    temporary.replace(path)


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--input',type=Path,required=True)
    args.add_argument('--out',type=Path,required=True)
    args.add_argument('--resolution',type=int,default=192)
    args.add_argument('--detail-resolution',type=int,default=288)
    args.add_argument('--internal-resolution',type=int,default=448)
    args.add_argument('--references-only',action='store_true')
    options = args.parse_args(sys.argv[sys.argv.index('--')+1:])
    resolutions = [options.resolution,options.resolution,options.detail_resolution,options.internal_resolution]
    if not all(64 <= value <= 512 for value in resolutions):
        raise ValueError('Resolution outside 64..512')
    source_sha = hashlib.file_digest(options.input.open('rb'),'sha256').hexdigest()
    if source_sha != SOURCE_SHA:
        raise ValueError('Source differs from the inspected 3DAnatomyman master')
    bpy.ops.wm.open_mainfile(filepath=str(options.input.resolve()),load_ui=False,use_scripts=False)
    top = bound_height(bpy.data.objects['skin'])
    bottom = top-.38
    for obj in list(bpy.data.objects):
        if obj.type=='MESH' and bound_height(obj)<bottom:
            mesh=obj.data;bpy.data.objects.remove(obj,do_unlink=True)
            if mesh.users==0:bpy.data.meshes.remove(mesh)
    gc.collect()
    raw = [layer_mesh(layer,bottom) for layer in LAYERS]
    for obj in list(bpy.data.objects):
        if obj.type=='MESH':
            mesh=obj.data;bpy.data.objects.remove(obj,do_unlink=True)
            if mesh.users==0:bpy.data.meshes.remove(mesh)
    gc.collect()
    all_points = np.asarray([p for points,_,_ in raw for p in points])
    low,high = all_points.min(axis=0),all_points.max(axis=0)
    center = Vector(tuple(float(v) for v in (low+high)/2))
    scale = max(high-low)*1.12
    root = options.out;root.mkdir(parents=True,exist_ok=True)
    samples, layers, bvhs = [], [], []
    for layer_id,(points,triangles,names) in enumerate(raw):
        bvh = BVHTree.FromPolygons([Vector(p)-center for p in points],triangles,all_triangles=True)
        bvhs.append(bvh)
        if options.references_only:continue
        start, views = len(samples), []
        resolution = resolutions[layer_id]
        for elevation in [-45,0,45]:
            for azimuth in range(0,360,30):
                az,el = math.radians(azimuth),math.radians(elevation)
                direction = Vector((math.sin(az)*math.cos(el),math.sin(el),math.cos(az)*math.cos(el)))
                right = Vector((math.cos(az),0,-math.sin(az)))
                up = direction.cross(right).normalized()
                gray = np.zeros((resolution,resolution),dtype=np.float32)
                normal = np.zeros((resolution,resolution,3),dtype=np.float32)
                depth = np.zeros((resolution,resolution),dtype=np.float32)
                for y in range(resolution):
                    for x in range(resolution):
                        origin=direction+right*((x+.5)/resolution-.5)*scale+up*((y+.5)/resolution-.5)*scale
                        p,n,face,distance=bvh.ray_cast(origin,-direction,2)
                        if p is None or n.dot(direction)<.03:continue
                        gray[y,x]=1;normal[y,x]=n;depth[y,x]=distance
                        samples.append((*p,-2.,*n,scale/resolution*FOOTPRINT[layer_id],1.,1.,1.,1.,PALETTE[layer_id][3],0.,0.,float(layer_id),*n,1.))
                view=f'layer{layer_id}-az{azimuth:03d}-el{elevation:+03d}.npz'
                save_npz(root/view,gray=gray,normal=normal,depth=depth,direction=np.asarray(direction),right=np.asarray(right),up=np.asarray(up),scale=scale)
                views.append(view)
                print('CAPTURE',layer_id,azimuth,elevation,len(samples),flush=True)
        layers.append({'id':layer_id,'name':LAYERS[layer_id],'sample_offset':start,'sample_count':len(samples)-start,'source_objects':names,'source_vertices':len(points),'source_triangles':len(triangles),'views':views})
    if not options.references_only:
        half = (high-low)/2
        corners = [(x*half[0],y*half[1],z*half[2]) for x in [-1,1] for y in [-1,1] for z in [-1,1]]
        box = [(0,1,3),(0,3,2),(4,6,7),(4,7,5),(0,4,5),(0,5,1),(2,3,7),(2,7,6),(0,2,6),(0,6,4),(1,5,7),(1,7,3)]
        (root/'vertices.bin').write_bytes(b''.join(struct.pack('<24f',*p,1.,0.,0.,0.,0.,0.,0.,0.,0.,0.,1.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.) for p in corners))
        (root/'triangles.bin').write_bytes(b''.join(struct.pack('<4I',*t,0) for t in box))
        (root/'samples.bin').write_bytes(np.asarray(samples,dtype='<f4').tobytes())
        master={'schema':3,'kind':'lie-anatomy25-rigid','vertex_stride':96,'sample_stride':80,'sample_count':len(samples),'invocation_count':len(samples),'vertex_count':8,'triangle_count':12,'layers':layers,'palette':PALETTE,'capture_resolution_by_layer':resolutions,'footprint_scale_by_layer':FOOTPRINT,'capture_scale':float(scale),'target':[0,0,0],'pivot':[0,0,0],'source_sha256':source_sha,'source':'https://always3d.gumroad.com/l/haJWL','author':'Always3D','license':'CC-BY-SA-2.1-JP','license_url':'https://creativecommons.org/licenses/by-sa/2.1/jp/','credit':'3DAnatomyman by Always3D; derivative of BodyParts3D © DBCLS. Cropped and captured for Lie.','rig':'rigid-bust-only','omissions':['hair pigment','body rig','facial expressions','cut surfaces','complete game gore'],'buffers':{name:{'bytes':(root/name).stat().st_size,'sha256':hashlib.file_digest((root/name).open('rb'),'sha256').hexdigest()} for name in ['vertices.bin','triangles.bin','samples.bin']}}
        (root/'master.json').write_text(json.dumps(master,indent=2)+'\n')
    # Independent perspective rays hit cropped source surfaces, not captures.
    size=512;fov=math.tan(math.radians(35)/2);distance=.95
    for mask in [15,14,12,8]:
        owners=np.full((size,size),-1,dtype=np.int32);depths=np.zeros((size,size),dtype=np.float32)
        eye=Vector((0,0,distance))
        for y in range(size):
            for x in range(size):
                ray=Vector(((2*(x+.5)/size-1)*fov,(1-2*(y+.5)/size)*fov,-1)).normalized()
                best=10
                for layer_id,bvh in enumerate(bvhs):
                    if not mask & (1<<layer_id):continue
                    p,n,face,t=bvh.ray_cast(eye,ray,2)
                    if p is not None and t<best:
                        best=t;owners[y,x]=layer_id;depths[y,x]=(eye-p).z
        save_npz(root/f'native-mask{mask}.npz',owners=owners,depth=depths)
        print('NATIVE',mask,flush=True)
    print('ANATOMY_REFERENCES' if options.references_only else 'ANATOMY_MASTER',len(samples),flush=True)


if __name__=='__main__':main()
