"""Original neutral eye and destructible masonry masters, captured in Blender.

Only ray-captured appearance points are drawn at runtime. Source surfaces are
editable authoring/physics data. All instances share one immutable library.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1] / 'gpu_compute'
PITCH = (.252, .076)
BRICK = (.24, .065, .11)
IRIS_INNER, IRIS_OUTER, EYE_RADIUS = .0017, .006, .012


def mesh_object(name, points, faces, zones, cells=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    zone = mesh.attributes.new('lie_zone', 'INT', 'FACE')
    cell = mesh.attributes.new('lie_cell', 'INT', 'FACE')
    for i, p in enumerate(mesh.polygons):
        zone.data[i].value = zones[i]
        cell.data[i].value = cells[i] if cells else 0
        p.material_index = zones[i]
    for i in range(8):
        mat = bpy.data.materials.get('LieNeutral_%d' % i)
        if mat is None:
            mat = bpy.data.materials.new('LieNeutral_%d' % i)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get('Principled BSDF')
            bsdf.inputs['Base Color'].default_value = (.55, .55, .55, 1)
            bsdf.inputs['Roughness'].default_value = .55
        mesh.materials.append(mat)
    return obj


def append_box(points, faces, zones, cells, center, size, zone, cell=0):
    base = len(points)
    for x, y, z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                    (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
        points.append(tuple(center[k] + q*size[k]*.5 for k, q in enumerate((x,y,z))))
    for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]:
        faces.append(tuple(base+i for i in f)); zones.append(zone); cells.append(cell)


def masonry(name, tile=False, coated=False):
    points, faces, zones, cells = [], [], [], []
    count = 2 if tile else 1
    for row in range(count):
        for col in range(count):
            center = ((col-(count-1)*.5)*PITCH[0], (row-(count-1)*.5)*PITCH[1], 0)
            append_box(points,faces,zones,cells,center,BRICK,3,row*2+col)
    if tile:
        append_box(points,faces,zones,cells,(0,0,-.001),(.012,PITCH[1]*2,.108),4)
        append_box(points,faces,zones,cells,(0,0,-.001),(PITCH[0]*2,.011,.108),4)
    if coated:
        size=(PITCH[0]*count,PITCH[1]*count,.005)
        append_box(points,faces,zones,cells,(0,0,.0575),size,5)
    obj=mesh_object(name,points,faces,zones,cells)
    return obj


def eye():
    points, faces, zones = [], [], []
    segments, rings = 128, 48
    theta0=math.asin(IRIS_OUTER/EYE_RADIUS)
    for j in range(rings+1):
        theta=theta0+(math.pi-theta0-.0001)*j/rings
        for i in range(segments):
            phi=2*math.pi*i/segments
            points.append((EYE_RADIUS*math.sin(theta)*math.cos(phi),
                           EYE_RADIUS*math.sin(theta)*math.sin(phi),EYE_RADIUS*math.cos(theta)))
    for j in range(rings):
        for i in range(segments):
            k=j*segments+i;ni=j*segments+(i+1)%segments
            faces.append((k,k+segments,ni+segments,ni));zones.append(0)
    base=len(points)
    for j in range(13):
        r=IRIS_INNER+(IRIS_OUTER-IRIS_INNER)*j/12
        for i in range(segments):
            phi=2*math.pi*i/segments;points.append((r*math.cos(phi),r*math.sin(phi),.0103923))
    for j in range(12):
        for i in range(segments):
            k=base+j*segments+i;ni=base+j*segments+(i+1)%segments
            faces.append((k,k+segments,ni+segments,ni));zones.append(1)
    center=len(points);points.append((0,0,.0103913))
    ring=len(points)
    for i in range(segments):
        phi=2*math.pi*i/segments;points.append((IRIS_INNER*math.cos(phi),IRIS_INNER*math.sin(phi),.0103913))
    for i in range(segments):faces.append((center,ring+i,ring+(i+1)%segments));zones.append(2)
    obj=mesh_object('eye',points,faces,zones)
    obj['lie_iris_color']='runtime linear RGB; grayscale fibers are preserved'
    obj['lie_pupil_radius_range_m']=[.0008,.0032]
    obj['lie_cornea']='captured sphere-normal clearcoat approximation; no refraction'
    return obj


def fragments():
    # Four convex Voronoi cells partition the actual brick, including internal
    # cut faces. Their master points are shared by every destroyed brick.
    seeds=[Vector((-.055,-.015,-.014)),Vector((.055,-.017,.008)),
           Vector((-.065,.015,.011)),Vector((.063,.016,-.009))]
    result=[]
    for index, seed in enumerate(seeds):
        obj=masonry('fragment_%d'%index)
        bm=bmesh.new();bm.from_mesh(obj.data)
        for other in seeds:
            if other==seed:continue
            n=(other-seed).normalized();mid=(other+seed)*.5
            cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                    plane_co=mid,plane_no=n,dist=1e-7,clear_outer=True,clear_inner=False)
            border=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
            if border:
                fill=bmesh.ops.holes_fill(bm,edges=border,sides=0)
                for face in fill['faces']:face.material_index=6
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data);bm.free();obj.data.update()
        zone=obj.data.attributes.get('lie_zone')
        for p in obj.data.polygons:zone.data[p.index].value=p.material_index
        result.append(obj)
    return result


def geometry(obj):
    mesh=obj.data;mesh.calc_loop_triangles()
    points=[v.co.copy() for v in mesh.vertices]
    faces=[tuple(t.vertices) for t in mesh.loop_triangles]
    zones=[mesh.attributes['lie_zone'].data[t.polygon_index].value for t in mesh.loop_triangles]
    cells=[mesh.attributes['lie_cell'].data[t.polygon_index].value for t in mesh.loop_triangles]
    low=Vector(tuple(min(p[k] for p in points) for k in range(3)))
    high=Vector(tuple(max(p[k] for p in points) for k in range(3)))
    center=(low+high)*.5 if obj.name.startswith('fragment') else Vector((0,0,0))
    points=[p-center for p in points]
    return points,faces,zones,cells,center,high-low


def gray_at(name,p,zone,cell):
    if zone==2:return .007
    if zone==1:
        phi=math.atan2(p.y,p.x);r=math.hypot(p.x,p.y)
        fibers=math.sin(phi*119+math.sin(phi*23)*2.5+r*2300)
        detail=math.sin(phi*271-r*3900)
        ring=math.exp(-((r-.0058)/.00032)**2)
        return min(max(.47+.16*fibers+.065*detail-.27*ring,.07),.8)
    if zone==0:
        phi=math.atan2(p.y,p.x);r=math.hypot(p.x,p.y)
        vein=max(math.cos(phi*19+math.sin(r*850)*.35),0)**48
        return .79-.10*vein
    if zone==4:return .40+.015*math.sin(p.x*510+p.y*710)
    if zone==5:return .78+.025*math.sin(p.x*900)*math.sin(p.y*1150)
    if zone==6:return .56+.06*math.sin(p.x*380+p.z*410)*math.sin(p.y*810)
    if zone==7:return .26+.025*math.sin(p.x*25)*math.sin(p.z*27)
    if name.startswith('tile') and zone==3:
        p=p-Vector(((cell%2-.5)*PITCH[0],(cell//2-.5)*PITCH[1],0))
    return .62+.07*math.sin(p.x*430+p.z*770)*math.sin(p.y*810)+.025*math.sin(p.x*1190+p.y*1480)


def png(path,rgba,size):
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    rows=b''.join(b'\0'+rgba[y*size*4:(y+1)*size*4] for y in range(size))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))


def capture(obj,resolution,out):
    points,faces,zones,cells,center,size=geometry(obj)
    bvh=BVHTree.FromPolygons(points,faces,all_triangles=True)
    span=max(size)*1.12;spacing=span/resolution
    voxel=spacing*.70;unique={};views=[]
    for elevation in [-55,0,55]:
        el=math.radians(elevation)
        for azimuth in range(0,360,30):
            az=math.radians(azimuth)
            direction=Vector((math.sin(az)*math.cos(el),math.sin(el),math.cos(az)*math.cos(el)))
            right=Vector((math.cos(az),0,-math.sin(az)));up=direction.cross(right).normalized()
            origin=direction*span*2
            rgba=bytearray(resolution*resolution*4);normal_png=bytearray(len(rgba));valid=0
            for y in range(resolution):
                for x in range(resolution):
                    ray_origin=origin+right*((x+.5)/resolution-.5)*span+up*(.5-(y+.5)/resolution)*span
                    hit,n,index,_=bvh.ray_cast(ray_origin,-direction,span*4)
                    if hit is None:continue
                    zone,cell=zones[index],cells[index]
                    if obj.name=='floor':zone=7
                    if obj.name=='eye' and zone==0:n=hit.normalized()
                    front=n.dot(direction)
                    if front<=.08:continue
                    gray=gray_at(obj.name,hit+center,zone,cell)
                    offset=(y*resolution+x)*4
                    rgba[offset:offset+4]=bytes([round(gray*255)]*3+[255])
                    normal_png[offset:offset+4]=bytes([round((v*.5+.5)*255) for v in n]+[255])
                    key=tuple(round(hit[k]/voxel) for k in range(3))+(zone,cell)
                    rough=.62 if zone in (3,6) else .86 if zone in (4,5,7) else .45 if zone==1 else .35
                    sample=tuple(hit)+(spacing*.85,)+tuple(n)+(gray,float(zone),float(cell),rough,0.)
                    if key not in unique or front>unique[key][0]:unique[key]=(front,sample)
                    valid+=1
            views.append({'azimuth':azimuth,'elevation':elevation,'valid_pixels':valid})
            if elevation==0 and azimuth in (0,60,180):
                png(out/(obj.name+'-az%03d-gray.png'%azimuth),rgba,resolution)
                png(out/(obj.name+'-az%03d-normal.png'%azimuth),normal_png,resolution)
    fine=[entry[1] for entry in unique.values()]
    coarse={}
    for sample in fine:
        key=tuple(round(sample[k]/(voxel*2.5)) for k in range(3))+(int(sample[8]),int(sample[9]))
        coarse.setdefault(key,sample[:3]+(sample[3]*2.5,)+sample[4:])
    coarse=list(coarse.values())
    return fine,coarse,{'capture_views':views,'bounds_size':list(size),'origin_offset':list(center),
            'collision_vertices':[list(p) for p in points], 'triangle_count':len(faces),
            'fine_count':len(fine),'coarse_count':len(coarse)}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resolution',type=int,default=96)
    args=parser.parse_args(__import__('sys').argv[__import__('sys').argv.index('--')+1:] if '--' in __import__('sys').argv else [])
    if not 64<=args.resolution<=192:raise ValueError('Capture resolution outside authoring contract')
    assets=ROOT/'assets/lie22';out=ROOT/'captures/modular22';assets.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    objects=[eye(),masonry('brick'),masonry('coated_brick',False,True),masonry('tile_brick',True),masonry('tile_coat',True,True)]+fragments()
    points,faces,zones,cells=[],[],[],[]
    append_box(points,faces,zones,cells,(0,-.005,0),(2.4,.01,1.6),7)
    objects.append(mesh_object('floor',points,faces,zones,cells))
    bpy.ops.wm.save_as_mainfile(filepath=str(assets/'modular-masters.blend'))
    catalog={'schema':1,'source':'Original procedural Blender masters; project license',
        'capture_resolution':args.resolution,'stride':48,'original_mesh_drawn':False,'eye':{'radius':EYE_RADIUS,'iris_inner':IRIS_INNER,'iris_outer':IRIS_OUTER},
        'brick_size':list(BRICK),'pitch':list(PITCH),'masters':{}}
    data=array('f');oracles={}
    for obj in objects:
        fine,coarse,metadata=capture(obj,args.resolution,out)
        metadata['levels']=[{'start':len(data)//12,'count':len(fine)}]
        for sample in fine:data.extend(sample)
        metadata['levels'].append({'start':len(data)//12,'count':len(coarse)})
        for sample in coarse:data.extend(sample)
        catalog['masters'][obj.name]=metadata
        print('LIE22 CAPTURE',obj.name,len(fine),len(coarse),flush=True)
        pts,faces,zones,cells,center,size=geometry(obj)
        oracles[obj.name]={'vertices':[list(p) for p in pts],'triangles':faces,'zones':zones,'cells':cells}
    raw=data.tobytes();(out/'library.bin').write_bytes(raw)
    catalog['sample_count']=len(data)//12;catalog['bytes']=len(raw);catalog['sha256']=hashlib.sha256(raw).hexdigest()
    (out/'catalog.json').write_text(json.dumps(catalog,indent=2)+'\n')
    (assets/'source-surfaces.json').write_text(json.dumps(oracles)+'\n')
    print('LIE22 LIBRARY',catalog['sample_count'],len(raw),'bytes',flush=True)


if __name__=='__main__':main()
