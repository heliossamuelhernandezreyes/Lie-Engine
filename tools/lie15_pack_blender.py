"""Object-local capture packing for arbitrary opaque masters; no light variants."""
import hashlib,json,struct,sys
from pathlib import Path
import bpy
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree

def lie(p): return Vector((p.x,p.z,-p.y))
def pack(root):
    manifest=json.loads((root/'manifest.json').read_text()); resolution=manifest['resolution'][0]
    if resolution!=128 or manifest['schema_version']!=2: raise ValueError('128px schema-2 required')
    triangles=json.loads((root.parents[1]/'assets/lie15/source-triangles.json').read_text())
    verts=[p for tri in triangles for p in tri]; bvh=BVHTree.FromPolygons(verts,[(i,i+1,i+2) for i in range(0,len(verts),3)],all_triangles=True)
    near,far=[manifest['linear_depth_meters'][k] for k in ['near','far']]
    center=Vector(manifest['center_blender']); scale=manifest['orthographic_scale']
    points=[]; views=[]; rejected=0
    for item in manifest['views']:
        channels={}
        for key in ['albedo','normal','depth']:
            image=bpy.data.images.load(str(root/item['channels'][key]),check_existing=False); image.colorspace_settings.name='Non-Color'
            channels[key]=list(image.pixels[:]); bpy.data.images.remove(image)
        matrix=Matrix(item['camera_matrix_blender']); origin=lie(matrix.translation-center)
        right,up,forward=lie(matrix.col[0].xyz),lie(matrix.col[1].xyz),-lie(matrix.col[2].xyz); start=len(points)
        for y in range(resolution):
            for x in range(resolution):
                pix=((resolution-1-y)*resolution+x)*4; rgba=channels['albedo'][pix:pix+4]; z=channels['depth'][pix]
                n=lie(Vector([v*2-1 for v in channels['normal'][pix:pix+3]])).normalized()
                if rgba[3]<.99 or n.length_squared<.5 or not 0<=z<=1: continue
                p=origin+((x+.5)/resolution-.5)*scale*right+(.5-(y+.5)/resolution)*scale*up+(near+z*(far-near))*forward
                nearest=bvh.find_nearest(p)
                if nearest[0] is None or nearest[3]>.012 or any(abs(v)>.512 for v in p): rejected+=1; continue
                if max(rgba[:3])-min(rgba[:3])>.002: raise ValueError('Master not grayscale')
                axis=max(range(3),key=lambda k:abs(n[k])); node=axis*2+int(n[axis]>0)
                points.append([*p,rgba[0],*n,float(node)])
        views.append({'start':start,'count':len(points)-start,'direction':list(origin.normalized()),'azimuth':item['azimuth_degrees'],'elevation':item['elevation_degrees']})
    patches=[]; probes=[]
    for node in range(6):
        normal=[0,0,0]; normal[node//2]=-1 if node%2==0 else 1
        selected=[(i,p) for i,p in enumerate(points) if int(p[7])==node]
        if not selected: raise ValueError('Missing patch')
        # Node positions describe coarse invisible boxes. Captured pixel normals
        # and actual positions retain all mesh details for visible direct light.
        patches.append({'position':[v*.5 for v in normal],'normal':normal,'area':1,'gray_mean':sum(p[3] for _,p in selected)/len(selected)})
        probes.append(min(selected,key=lambda q:sum((q[1][k]-normal[k]*.5)**2 for k in range(3)))[0])
    data=b''.join(struct.pack('<8f',*p) for p in points); (root/'master-samples.bin').write_bytes(data)
    result={'schema':1,'master_id':'arcont-kenney-factory-box-small-neutral-v1','sample_count':len(points),'sample_stride_bytes':32,'views':views,'patches':patches,'bounds':[[-.5]*3,[.5]*3],'collision':{'kind':'box','half_extents':[.5]*3},'probe_samples':probes,'rejected_boundary_pixels':rejected,'normal_space':'object-local Lie XYZ','neutral_lighting':True,'normal_maps_per_view':1,'capture_light_variants_per_view':0,'sample_sha256':hashlib.sha256(data).hexdigest()}
    (root/'master.json').write_text(json.dumps(result,indent=2)+'\n'); print('LIE15 MASTER',len(views),'views',len(points),'samples')
if __name__=='__main__': pack(Path(sys.argv[sys.argv.index('--')+1]).resolve())
