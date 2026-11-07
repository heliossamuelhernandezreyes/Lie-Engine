"""Clip the genuine canonical scan; close the cut with declared authored clay.

Original surfaces and vertex color are retained. This is a saw cut, never a
scaled full brick. Output GLB uses LIE's already-authored Y-up meter frame.
"""
import argparse,hashlib,json,struct,sys
from pathlib import Path
import bpy,bmesh
import numpy as np
from mathutils import Vector

def glb(path,parts):
    data=bytearray();views=[];accessors=[];primitives=[]
    def accessor(a,kind,component):
        a=np.ascontiguousarray(a);offset=len(data);data.extend(a.tobytes());data.extend(b'\0'*((-len(data))%4));v=len(views);views.append(dict(buffer=0,byteOffset=offset,byteLength=a.nbytes));n=len(accessors)
        spec=dict(bufferView=v,componentType=component,count=len(a),type=kind)
        if kind=='VEC3':spec.update(min=a.min(0).astype(float).tolist(),max=a.max(0).astype(float).tolist())
        accessors.append(spec);return n
    for index,(vertices,colors,faces) in enumerate(parts):
        primitives.append(dict(attributes=dict(POSITION=accessor(vertices.astype('<f4'),'VEC3',5126),COLOR_0=accessor(colors.astype('<f4'),'VEC4',5126)),indices=accessor(faces.astype('<u4').ravel(),'SCALAR',5125),material=index))
    doc=dict(asset=dict(version='2.0',generator='LIE authored rigid scan saw cut'),scene=0,scenes=[dict(nodes=[0])],nodes=[dict(mesh=0)],meshes=[dict(primitives=primitives)],
             materials=[dict(name='Original source COLOR_0',pbrMetallicRoughness=dict(metallicFactor=0,roughnessFactor=.6)),dict(name='Authored exposed cut clay, not scanned',pbrMetallicRoughness=dict(metallicFactor=0,roughnessFactor=.85))],buffers=[dict(byteLength=len(data))],bufferViews=views,accessors=accessors)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(data))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(data),0x004e4942)+data)

def make(source,output):
    a=np.load(source);original=a['vertices'];vertices,first,inverse=np.unique(original,axis=0,return_index=True,return_inverse=True);faces=inverse[a['triangles']];colors=a['colors'][first]
    if not np.array_equal(a['colors'],colors[inverse]):raise ValueError('Color seams need separate preservation')
    output.mkdir(parents=True,exist_ok=True);records={}
    for name,plane,left in [('half_left',-.004,True),('half_right',.004,False)]:
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices.tolist(),[],faces.tolist());mesh.update()
        attr=mesh.color_attributes.new(name='SourceColor',type='FLOAT_COLOR',domain='POINT');attr.data.foreach_set('color',np.column_stack([colors,np.ones(len(colors))]).astype(np.float32).ravel())
        bm=bmesh.new();bm.from_mesh(mesh)
        # glTF splits vertices at normal/color seams. Reconnect coincident
        # geometry so the saw section is a continuous boundary loop.
        cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=Vector((plane,0,0)),plane_no=Vector((1,0,0)),clear_outer=left,clear_inner=not left)
        edges=[e for e in bm.edges if e.is_boundary and all(abs(v.co.x-plane)<2e-7 for v in e.verts)]
        print('CUT TOPOLOGY',name,len(bm.verts),len(bm.faces),'boundary',sum(e.is_boundary for e in bm.edges),'plane edges',len(edges),'plane range',min(v.co.x for v in bm.verts),max(v.co.x for v in bm.verts),flush=True)
        caps=bmesh.ops.holes_fill(bm,edges=edges,sides=0)['faces']
        if not caps:raise ValueError('No closed authored cut cap')
        for f in caps:f.material_index=1
        bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.normal_update();bm.verts.ensure_lookup_table();bm.verts.index_update()
        if any(e.is_boundary for e in bm.edges):raise ValueError('Saw cut is not closed')
        layer=bm.verts.layers.float_color.get('SourceColor');v=np.array([tuple(p.co) for p in bm.verts],dtype='<f4');rgb=np.array([tuple(p[layer]) for p in bm.verts],dtype='<f4')
        if left and v[:,0].max()>plane+2e-7 or not left and v[:,0].min()<plane-2e-7:raise ValueError('Wrong saw-cut side')
        source_faces=[];cap_faces=[]
        for f in bm.faces:
            if f.material_index==1:
                if (f.normal.x>0)!=left:f.normal_flip()
                cap_faces.append([p.index for p in f.verts])
            else:source_faces.append([p.index for p in f.verts])
        cap_color=np.tile(np.array([.30,.18,.125,1],dtype='<f4'),(len(v),1))
        path=output/(name+'.glb');glb(path,[(v,rgb,np.array(source_faces)),(v,cap_color,np.array(cap_faces))])
        records[name]=dict(file=path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),cut_plane_m=plane,cut_normal=[1 if left else -1,0,0],original_surface_triangles=len(source_faces),authored_cap_triangles=len(cap_faces),bounds_min=v.min(0).tolist(),bounds_max=v.max(0).tolist(),source_canonical_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),cap_color_linear=[.30,.18,.125],cap_roughness=.85,cap_origin='authored exposed clay; not measured or part of the original scan')
        bm.free();bpy.data.meshes.remove(mesh);print('SAW CUT',name,records[name],flush=True)
    (output/'cuts.json').write_text(json.dumps(records,indent=2)+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--canonical',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);make(a.canonical,a.output)
