"""Higher-density neutral human captures, retaining the independent Blender rig."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie20_prepare_blender import ROOT,author,capture,pose,lie

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resolution',type=int,default=384);parser.add_argument('--no-reference',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    root=ROOT.parents[1]/'captures/human_quality';root.mkdir(parents=True,exist_ok=True)
    obj,rig,rest,weights,lid,jaw,uvs,color,normal,spec=author()
    triangles,samples,views=capture(obj,rest,uvs,color,normal,spec,root,args.resolution,native_tangents=True)
    packets={'vertices.bin':b''.join(struct.pack('<12f',*p,w,*ld,0,*jd,0) for p,w,ld,jd in zip(rest,weights,lid,jaw)),
             'triangles.bin':b''.join(struct.pack('<4I',*t,0) for t in triangles),
             'samples.bin':b''.join(struct.pack('<20f',*s) for s in samples)}
    for name,data in packets.items():(root/name).write_bytes(data)
    probe_indices=list(range(0,len(samples),max(1,len(samples)//128)))[:128]
    cases=[]
    for head,ls,jd in [(0,0,0),(-25,0,0),(25,0,0),(0,1,0),(0,0,1),(15,.7,.7)]:
        pose(obj,rig,head,ls,jd)
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());m=evaluated.to_mesh()
        vertices=[lie(v.co) for v in m.vertices];expected=[]
        for index in probe_indices:
            s=samples[index];t=triangles[int(s[3])]
            p=sum((vertices[k]*w for k,w in zip(t,s[:3])),Vector())
            expected.append(list(p))
        evaluated.to_mesh_clear()
        cases.append({'head_yaw':head,'lid_squeeze':ls,'jaw_drop':jd,'probe_positions':expected})
    (root/'deformation-oracle.json').write_text(json.dumps({'probe_indices':probe_indices,'cases':cases},indent=2)+'\n')
    pose(obj,rig,0,0,0)
    source_path=ROOT/'human-master-quality.blend'
    for image in bpy.data.images:
        if image.source=='FILE':image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    manifest={'schema':1,'master_id':'lie-human-lee-perry-smith-v1','capture_resolution':args.resolution,'normal_capture':'native Blender loop tangent frames and strength interpolation','capture_views':views,
        'sample_count':len(samples),'vertex_count':len(rest),'triangle_count':len(triangles),'strides':{'sample':80,'vertex':48,'triangle':16},
        'buffers':{name:{'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in packets.items()},
        'pivot':[0,.155,0],'target':[0,.23,0],'orthographic_scale':.52,'normal_space':'Lie object XYZ','gray_filter_color_space':'linear RGB',
        'source_lock':'../../assets/lie20/source-lock.json','original_mesh_drawn':False,
        'shape_keys':['lid_squeeze','jaw_drop'],'limitations':['Closed-eye scan; no eyeballs, cornea, hair or mouth interior.','Correctives are experimental authored offsets; not anatomical expressions.','Specular scan converted to an artistic roughness approximation.','Human indirect illumination and complete shadow transport are not implemented.']}
    (root/'master.json').write_text(json.dumps(manifest,indent=2)+'\n')
    if not args.no_reference:
        from lie20_reference_blender import render_references
        render_references(obj,rig,root,pose)
    print('LIE21 MASTER',len(samples),'samples',len(rest),'invisible vertices',flush=True)


if __name__=='__main__':main()
