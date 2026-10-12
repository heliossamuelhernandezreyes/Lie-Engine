#!/usr/bin/env python3
"""Original mechanical masters / attributed 4K PBR maps / neutral Lie captures.

Coordinates: metres, Y up. No original meshes are rendered by the runtime.
Blender --background --python tools/lie_robot_prepare_blender.py -- --materials DIR
"""
import argparse
from array import array
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
import lie22_prepare_blender as mesh_base
from lie28_prepare_blender import atomic, bevel

ROOT=Path(__file__).resolve().parents[1]/'gpu_compute'
MAPS={}
MATERIALS={}
SIZES={'plate_flat':(.22,.34,.046),'plate_shell':(.23,.34,.12),
       'plate_bracket':(.16,.18,.10),'joint':(.164,.15,.164),
       'shaft':(.052,.5,.052),'cable':(.024,.5,.024),'ground':(3,.03,3)}
BONES=[('pelvis',-1,(0,.91,0)),('torso',0,(0,1.08,0)),('head',1,(0,1.62,0)),
 ('right_upper_arm',1,(-.32,1.46,0)),('right_forearm',3,(-.34,1.13,0)),('right_hand',4,(-.34,.83,.01)),
 ('left_upper_arm',1,(.32,1.46,0)),('left_forearm',6,(.34,1.13,0)),('left_hand',7,(.34,.83,.01)),
 ('right_thigh',0,(-.135,.91,0)),('right_shin',9,(-.135,.51,.02)),('right_foot',10,(-.135,.105,.045)),
 ('left_thigh',0,(.135,.91,0)),('left_shin',12,(.135,.51,.02)),('left_foot',13,(.135,.105,.045))]

def revolved(points,faces,zones,cells,center,profile,zone=2,axis=(0,1,0),segments=48):
    """Closed lathed solid with physical collars and grooves."""
    offset=len(points);q=Vector((0,1,0)).rotation_difference(Vector(axis))
    for h,r in profile:
        for i in range(segments):
            p=q@Vector((r*math.cos(i*math.tau/segments),h,r*math.sin(i*math.tau/segments)))+Vector(center)
            points.append(tuple(p))
    for row in range(len(profile)-1):
        for col in range(segments):
            a=offset+row*segments+col;b=offset+row*segments+(col+1)%segments
            faces.append((a,a+segments,b+segments,b));zones.append(zone);cells.append(0)
    faces.append(tuple(offset+i for i in range(segments)));zones.append(zone);cells.append(0)
    faces.append(tuple(offset+(len(profile)-1)*segments+i for i in reversed(range(segments))));zones.append(zone);cells.append(0)

def screw(points,faces,zones,cells,x,y,z):
    revolved(points,faces,zones,cells,(x,y,z),[(-.001,.0045),(0,.008),(.002,.008),(.003,.006)],2,(0,0,1),32)
    mesh_base.append_box(points,faces,zones,cells,(x,y,z+.0032),(.010,.0015,.0006),3)

def plate(name):
    p,f,z,c=[],[],[],[]
    if name=='plate_flat':
        mesh_base.append_box(p,f,z,c,(0,0,0),(.22,.34,.032),1)
        obj=bevel(mesh_base.mesh_object(name,p,f,z,c),.009)
        # Build details after the panel bevel, keeping small fasteners crisp.
        p=[tuple(v.co) for v in obj.data.vertices];f=[tuple(v.vertices) for v in obj.data.polygons]
        z=[obj.data.attributes['lie_zone'].data[v.index].value for v in obj.data.polygons];c=[0]*len(f)
        for x in [-.082,.082]:
            for y in [-.135,.135]:screw(p,f,z,c,x,y,.016)
        for y in [-.09,-.06,-.03]:mesh_base.append_box(p,f,z,c,(0,y,.0168),(.095,.003,.002),3)
        mesh_base.append_box(p,f,z,c,(0,.067,.0175),(.095,.012,.003),3)
        for x in [-.026,.026]:mesh_base.append_box(p,f,z,c,(x,.067,.0193),(.035,.005,.001),6)
        mesh_base.append_box(p,f,z,c,(0,.114,.017),(.105,.010,.002),4)
        bpy.data.objects.remove(obj,do_unlink=True)
    elif name=='plate_shell':
        # Curved armor sheet with an actual inner face and exposed thickness.
        steps=32;half=.115;radius=.19
        for layer in [0,.012]:
            for y in [-.17,.17]:
                for i in range(steps+1):
                    x=(i/steps*2-1)*half;depth=math.sqrt(radius*radius-x*x)-radius
                    p.append((x,y,depth+layer+.04))
        width=steps+1
        for layer in range(2):
            base=layer*width*2
            for i in range(steps):
                face=(base+i,base+i+1,base+width+i+1,base+width+i)
                f.append(face if layer==1 else tuple(reversed(face)));z.append(1);c.append(0)
        for row in [0,1]:
            for i in range(steps):
                a=row*width+i;f.append((a,a+width*2,a+width*2+1,a+1) if row==0 else (a,a+1,a+width*2+1,a+width*2));z.append(2);c.append(0)
        for i in [0,steps]:
            f.append((i,i+width,i+width*3,i+width*2) if i==0 else (i,i+width*2,i+width*3,i+width));z.append(2);c.append(0)
        for x in [-.075,.075]:
            for y in [-.13,.13]:screw(p,f,z,c,x,y,math.sqrt(radius*radius-x*x)-radius+.052)
        for y in [-.09,-.055,-.02,.015]:mesh_base.append_box(p,f,z,c,(0,y,.053),(.08,.003,.002),3)
        mesh_base.append_box(p,f,z,c,(0,.11,.053),(.11,.013,.003),4)
    else:
        mesh_base.append_box(p,f,z,c,(0,0,.025),(.16,.18,.020),5)
        mesh_base.append_box(p,f,z,c,(-.07,0,-.012),(.020,.18,.094),5)
        obj=bevel(mesh_base.mesh_object(name,p,f,z,c),.003)
        p=[tuple(v.co) for v in obj.data.vertices];f=[tuple(v.vertices) for v in obj.data.polygons]
        z=[obj.data.attributes['lie_zone'].data[v.index].value for v in obj.data.polygons];c=[0]*len(f)
        for y in [-.055,.055]:screw(p,f,z,c,.015,y,.035)
        mesh_base.append_box(p,f,z,c,(.052,0,.036),(.018,.11,.002),4)
        bpy.data.objects.remove(obj,do_unlink=True)
    obj=mesh_base.mesh_object(name,p,f,z,c)
    return obj

def cylinder(name):
    p,f,z,c=[],[],[],[]
    if name=='joint':
        profile=[(-.075,.07),(-.065,.082),(-.043,.082),(-.037,.062),(.037,.062),(.043,.082),(.065,.082),(.075,.07)]
        revolved(p,f,z,c,(0,0,0),profile,2,segments=64)
        for i in range(8):
            a=i*math.tau/8;revolved(p,f,z,c,(.048*math.cos(a),.077,.048*math.sin(a)),[(-.002,.005),(0,.007),(.002,.007)],5,segments=16)
    elif name=='shaft':
        revolved(p,f,z,c,(0,0,0),[(-.25,.018),(-.24,.025),(-.22,.025),(-.215,.018),(.215,.018),(.22,.025),(.24,.025),(.25,.018)],2,segments=48)
    else:
        # Corrugations are source geometry. Runtime bends these captured samples.
        profile=[]
        for i in range(129):
            y=i/128*.5-.25;r=.009+.001*math.cos(i*math.pi/2)
            if i in (0,1,127,128):r=.012
            profile.append((y,r))
        revolved(p,f,z,c,(0,0,0),profile,3,segments=24)
    return mesh_base.mesh_object(name,p,f,z,c)

def load_materials(directory):
    provenance=json.loads((directory/'provenance.json').read_text())
    for item in provenance:
        path=directory/item['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256']
        image=bpy.data.images.load(str(path));image.colorspace_settings.name='sRGB' if item['map']=='Diffuse' else 'Non-Color'
        values=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(values)
        pixels=np.rint(values.reshape(image.size[1],image.size[0],4)*255).clip(0,255).astype(np.uint8)
        if item['map'] in ('Rough','Metal'):pixels=pixels[:,:,0].copy()
        elif item['map']=='arm':pixels=pixels[:,:,2].copy()
        else:pixels=pixels[:,:,:3].copy()
        MAPS[(item['asset'],item['map'])]=(image,pixels)
    for zone in range(8):
        m=bpy.data.materials.new(['unused','Blue coated steel','Machined steel','Cable rubber','Amber coating','Weathered steel','Cyan indicator','Studio floor'][zone]);m.use_nodes=True
        bsdf=m.node_tree.nodes.get('Principled BSDF')
        colors={0:(.2,.2,.2),2:(.53,.58,.64),3:(.008,.010,.014),4:(.75,.18,.022),6:(.008,.32,.52),7:(.045,.055,.07)}
        bsdf.inputs['Base Color'].default_value=(*colors.get(zone,(.4,.4,.4)),1)
        bsdf.inputs['Roughness'].default_value=.26 if zone==2 else .6 if zone==3 else .42
        bsdf.inputs['Metallic'].default_value=1 if zone==2 else 0
        if zone==6:
            bsdf.inputs['Emission Color'].default_value=(*colors[6],1);bsdf.inputs['Emission Strength'].default_value=4
        if zone in (1,5):
            asset='blue_metal_plate' if zone==1 else 'metal_plate_02'
            for key,socket in [('Diffuse','Base Color'),('Rough','Roughness')]:
                node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=MAPS[(asset,key)][0];m.node_tree.links.new(node.outputs['Color'],bsdf.inputs[socket])
            node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=MAPS[(asset,'arm' if zone==1 else 'Metal')][0]
            if zone==1:
                separate=m.node_tree.nodes.new('ShaderNodeSeparateColor');m.node_tree.links.new(node.outputs['Color'],separate.inputs['Color']);m.node_tree.links.new(separate.outputs['Blue'],bsdf.inputs['Metallic'])
            else:m.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Metallic'])
            node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=MAPS[(asset,'nor_gl')][0]
            normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.35;m.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);m.node_tree.links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
        MATERIALS[zone]=m
    return provenance

def uv_for(p,n):
    axis=max(range(3),key=lambda k:abs(n[k]));a,b=[(2,1),(0,2),(0,1)][axis]
    return (p[a]/.65+.42,p[b]/.65+.38)

def prepare_uv(obj):
    mesh=obj.data;mesh.materials.clear()
    for zone in range(8):mesh.materials.append(MATERIALS[zone])
    uv=mesh.uv_layers.new(name='Physical source UV')
    for face in mesh.polygons:
        face.material_index=mesh.attributes['lie_zone'].data[face.index].value
        for k in face.loop_indices:uv.data[k].uv=uv_for(mesh.vertices[mesh.loops[k].vertex_index].co,face.normal)

def bilinear(pixels,uv):
    h,w=pixels.shape[:2];x=(uv[0]%1)*w-.5;y=(uv[1]%1)*h-.5;a,b=math.floor(x),math.floor(y);u,v=x-a,y-b
    return (pixels[b%h,a%w].astype(np.float64)*(1-u)*(1-v)+pixels[b%h,(a+1)%w]*u*(1-v)+pixels[(b+1)%h,a%w]*(1-u)*v+pixels[(b+1)%h,(a+1)%w]*u*v)/255

def surface_material(zone,uv,p,n,tangent,bitangent):
    if zone in (1,5):
        asset='blue_metal_plate' if zone==1 else 'metal_plate_02'
        srgb=bilinear(MAPS[(asset,'Diffuse')][1],uv)
        color=np.where(srgb<=.04045,srgb/12.92,((srgb+.055)/1.055)**2.4)
        rough=float(bilinear(MAPS[(asset,'Rough')][1],uv));metal=float(bilinear(MAPS[(asset,'arm' if zone==1 else 'Metal')][1],uv))
        normal=bilinear(MAPS[(asset,'nor_gl')][1],uv)*2-1
        normal[0:2]*=.35
        shade=(tangent*float(normal[0])+bitangent*float(normal[1])+n*float(normal[2])).normalized()
        if shade.dot(n)<.3:shade=n
        return tuple(color),max(.18,min(.92,rough)),max(0,min(1,metal)),0,shade
    grain=.985+.015*math.sin(p.x*781+p.z*475)*math.sin(p.y*1200)
    color={0:(.2,.2,.2),2:(.53,.58,.64),3:(.008,.010,.014),4:(.75,.18,.022),6:(.008,.32,.52),7:(.045,.055,.07)}[zone]
    return tuple(v*grain for v in color),.26 if zone==2 else .64 if zone==3 else .42,1 if zone==2 else 0,4 if zone==6 else 0,n

def capture(obj,resolution,out,preserve_faces=False):
    pts,faces,zones,cells,center,size=mesh_base.geometry(obj);mesh=obj.data;triangles=list(mesh.loop_triangles)
    bvh=BVHTree.FromPolygons(pts,faces,all_triangles=True);extent=max(size);spacing=extent*1.10/resolution;voxel=spacing*.95
    supports=[];tangents=[];uvs=[]
    for tri in triangles:
        face=mesh.polygons[tri.polygon_index];axis=max(range(3),key=lambda k:abs(face.normal[k]));a,b=[(2,1),(0,2),(0,1)][axis]
        points=[pts[k] for k in face.vertices];supports.append((min(p[a] for p in points),min(p[b] for p in points),max(p[a] for p in points),max(p[b] for p in points)))
        tex=[mesh.uv_layers.active.data[k].uv.copy() for k in tri.loops];uvs.append(tex)
        pa,pb,pc=(pts[k] for k in tri.vertices);d1,d2=pb-pa,pc-pa;t1,t2=tex[1]-tex[0],tex[2]-tex[0];det=t1.x*t2.y-t1.y*t2.x
        if abs(det)>1e-9:
            t=(d1*t2.y-d2*t1.y)/det;b=(-d1*t2.x+d2*t1.x)/det
            tangents.append((t.normalized(),b.normalized()))
        else:
            t=face.normal.cross(Vector((0,1,0)) if abs(face.normal.y)<.9 else Vector((1,0,0))).normalized();tangents.append((t,face.normal.cross(t)))
    unique={};views=[]
    for eldeg in [-55,0,55]:
        el=math.radians(eldeg)
        for azdeg in range(0,360,30):
            az=math.radians(azdeg);direction=Vector((math.sin(az)*math.cos(el),math.sin(el),math.cos(az)*math.cos(el)))
            right=Vector((math.cos(az),0,-math.sin(az)));up=direction.cross(right).normalized()
            # Fit the view to source bounds, giving thin cables real transverse detail.
            rx=[p.dot(right) for p in pts];uy=[p.dot(up) for p in pts]
            sx=max(max(rx)-min(rx),extent*.08)*1.10;sy=max(max(uy)-min(uy),extent*.08)*1.10
            origin=direction*extent*2+right*((min(rx)+max(rx))*.5)+up*((min(uy)+max(uy))*.5)
            rgba=bytearray(resolution*resolution*4);valid=0
            for y in range(resolution):
                for x in range(resolution):
                    ro=origin+right*((x+.5)/resolution-.5)*sx+up*(.5-(y+.5)/resolution)*sy
                    hit,n,index,_=bvh.ray_cast(ro,-direction,extent*4)
                    if hit is None or n.dot(direction)<=.08:continue
                    a,b,c=(pts[k] for k in faces[index]);e,f,q=b-a,c-a,hit-a;ee,ff,ef=e.dot(e),f.dot(f),e.dot(f);den=ee*ff-ef*ef
                    if abs(den)<1e-16:continue
                    u=(ff*q.dot(e)-ef*q.dot(f))/den;v=(ee*q.dot(f)-ef*q.dot(e))/den
                    uv=uvs[index][0]*(1-u-v)+uvs[index][1]*u+uvs[index][2]*v
                    color,rough,metal,emission,shade=surface_material(zones[index],uv,hit,n,*tangents[index])
                    srgb=[q*12.92 if q<=.0031308 else 1.055*q**(1/2.4)-.055 for q in color]
                    offset=(y*resolution+x)*4;rgba[offset:offset+4]=bytes([max(0,min(255,round(q*255))) for q in srgb]+[255])
                    sample=tuple(hit)+(spacing*.90,)+tuple(n)+(1.,float(zones[index]),float(cells[index]),rough,metal)+tuple(color)+(emission,)+supports[index]+tuple(shade)+(0.,)
                    owner=triangles[index].polygon_index if preserve_faces else -1
                    key=tuple(round(hit[k]/voxel) for k in range(3))+(zones[index],owner)
                    front=n.dot(direction)
                    if key not in unique or front>unique[key][0]:unique[key]=(front,sample,owner)
                    valid+=1
            views.append(dict(azimuth=azdeg,elevation=eldeg,valid_pixels=valid))
            if azdeg in (0,60,180) and eldeg==0:mesh_base.png(out/f'{obj.name}-az{azdeg:03d}-albedo.png',rgba,resolution)
    fine=[v[1] for v in unique.values()];coarse={}
    multiplier=6 if preserve_faces else 3
    for _,s,owner in unique.values():
        key=tuple(round(s[k]/(voxel*multiplier)) for k in range(3))+(int(s[8]),owner)
        coarse.setdefault(key,s[:3]+(s[3]*multiplier,)+s[4:])
    return fine,list(coarse.values()),dict(bounds_size=list(size),origin_offset=list(center),capture_resolution=resolution,capture_views=views,triangle_count=len(faces),preserve_polygon_ownership=preserve_faces,coarse_spacing_multiplier=multiplier,collision_vertices=[list(p) for p in pts])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--materials',type=Path,required=True);parser.add_argument('--resolution',type=int,default=160)
    parser.add_argument('--bank-name',default='robot_modular');parser.add_argument('--bank-only',action='store_true');parser.add_argument('--refine-shaft',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);assert 96<=args.resolution<=192
    if Path(args.bank_name).name!=args.bank_name:raise ValueError('Use a bank basename')
    assets=ROOT/'assets/robot_modular';out=ROOT/'captures'/args.bank_name;assets.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
    if args.bank_only:
        bpy.ops.wm.open_mainfile(filepath=str(assets/'robot-masterkit.blend'))
        provenance=load_materials(args.materials);objects=[bpy.data.objects[name] for name in SIZES]
    else:
        bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
        provenance=load_materials(args.materials)
        objects=[plate(name) for name in ('plate_flat','plate_shell','plate_bracket')]+[cylinder(name) for name in ('joint','shaft','cable')]
        p,f,z,c=[],[],[],[];mesh_base.append_box(p,f,z,c,(0,-.015,0),(3,.03,3),7);objects.append(mesh_base.mesh_object('ground',p,f,z,c))
        for obj in objects:
            bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()
            prepare_uv(obj);bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
            bpy.ops.export_scene.gltf(filepath=str(assets/(obj.name+'.glb')),use_selection=True,export_format='GLB',export_yup=False)
            obj.asset_mark();obj.asset_data.author='Lie Engine';obj.asset_data.description='Original mechanical master, metres/Y-up. 4K CC0 maps attributed in provenance.json.'
        for image in bpy.data.images:
            if image.source=='FILE':image.pack()
        for obj in objects:obj.hide_set(obj.name!='plate_flat');obj.hide_render=obj.name!='plate_flat'
        bpy.ops.wm.save_as_mainfile(filepath=str(assets/'robot-masterkit.blend'))
    catalog=dict(schema=1,stride=96,capture_resolution=args.resolution,original_mesh_drawn=False,materials=provenance,
        source='Original mechanical geometry + 4K CC0 Poly Haven maps / Rob Tuytel',
        rig=[dict(name=name,parent=parent,pivot=list(pivot)) for name,parent,pivot in BONES],masters={})
    data=array('f');oracles={}
    for obj in objects:
        refined=args.refine_shaft and obj.name=='shaft'
        fine,coarse,metadata=capture(obj,args.resolution*2 if obj.name=='cable' or refined else args.resolution,out,refined);metadata['levels']=[]
        for samples in (fine,coarse):
            metadata['levels'].append(dict(start=len(data)//24,count=len(samples)))
            for sample in samples:data.extend(sample)
        catalog['masters'][obj.name]=metadata
        pts,faces,zones,cells,center,size=mesh_base.geometry(obj)
        oracles[obj.name]=dict(vertices=[list(p) for p in pts],triangles=faces,zones=zones,cells=cells,origin_offset=list(center),triangle_uvs=[[list(obj.data.uv_layers.active.data[k].uv) for k in t.loops] for t in obj.data.loop_triangles])
        print('ROBOT MASTER',obj.name,len(fine),len(coarse),flush=True)
    raw=data.tobytes()
    if len(raw)>64*1024*1024:raise ValueError('Bank exceeds 64 MiB; lower capture resolution')
    catalog.update(sample_count=len(data)//24,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    atomic(out/'library.bin',raw);atomic(out/'catalog.json',(json.dumps(catalog,indent=2)+'\n').encode())
    if not args.bank_only:
        atomic(assets/'source-surfaces.json',(json.dumps(oracles)+'\n').encode());atomic(assets/'provenance.json',(json.dumps(provenance,indent=2)+'\n').encode())
    print('ROBOT LIBRARY',catalog['sample_count'],len(raw),'bytes',flush=True)

if __name__=='__main__':main()
