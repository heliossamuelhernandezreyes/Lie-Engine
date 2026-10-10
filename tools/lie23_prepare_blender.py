"""Open the attributed scan, author eyelids and bind one reusable eye master.

The native armature, blink shape key and pupil shape keys supply independent
geometry oracles. Runtime appearance is captured; original meshes stay hidden.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie20_prepare_blender import author, barycentric, blender, capture, lie, ROOT
from lie22_prepare_blender import eye, capture as capture_eye

RADIUS=.012

def build_face():
    original,rig,rest,weights,_,_,uvs,color,normal,spec=author()
    original.data.calc_loop_triangles()
    old_faces=[tuple(t.vertices) for t in original.data.loop_triangles]
    bvh=BVHTree.FromPolygons(rest,old_faces,all_triangles=True)
    anchors=[]
    # Calibrated from the pinned scan's frontal geometry and texture, not
    # the approximate coordinates of LIE-20's closed-eye stress corrective.
    for x in [-.037,.034]:
        hit,_,_,_=bvh.ray_cast(Vector((x,.301,.4)),Vector((0,0,-1)),1)
        if hit is None:raise ValueError('Missing orbital landmark')
        anchors.append(Vector((x,.301,hit.z-.0125)))
    faces=[]
    removed=0
    for f in old_faces:
        center=sum((rest[k] for k in f),Vector())/3
        cut=any(((center.x-a.x)/.0155)**2+((center.y-a.y)/.0098)**2<1 and center.z>.035 for a in anchors)
        if cut:removed+=1
        else:faces.append(f)
    blink=[Vector() for _ in rest]
    regions=[0]*len(rest)
    segments,rows=96,12
    for side,a in enumerate(anchors):
        base=len(rest)
        for row in range(rows+1):
            t=row/rows
            for i in range(segments):
                phi=2*math.pi*i/segments;cs,sn=math.cos(phi),math.sin(phi)
                inner=Vector((.0117*cs,(.006 if sn>=0 else .0048)*sn,0))
                inner.z=math.sqrt(max(RADIUS**2-inner.x**2-inner.y**2,1e-8))+.00045
                outer_xy=Vector((a.x+.021*cs,a.y+.014*sn,.4))
                hit,_,ti,_=bvh.ray_cast(outer_xy,Vector((0,0,-1)),1)
                if hit is None:raise ValueError('Missing lid attachment')
                p=(a+inner)*(1-t)+hit*t
                # The two native rims overlap by less than one millimeter.
                # A positive gap, even 0.16 mm, exposes the iris at close range.
                closed=Vector((inner.x,-.00045*sn,math.sqrt(max(RADIUS**2-inner.x**2,1e-8))+.0006))
                delta=(closed-inner)*(1-t)**1.4
                # A closed lid must lie outside the entire eye hemisphere,
                # including intermediate rings where the original scan dips.
                target=p+delta;dx,dy=target.x-a.x,target.y-a.y
                inside=RADIUS**2-dx*dx-dy*dy
                if inside>0:target.z=max(target.z,a.z+math.sqrt(inside)+.00075)
                delta=target-p
                ray,_,ui,_=bvh.ray_cast(Vector((p.x,p.y,.4)),Vector((0,0,-1)),1)
                tri=old_faces[ui];bary=barycentric(ray,*(rest[k] for k in tri))
                uv=sum((Vector(uvs[k])*w for k,w in zip(tri,bary)),Vector((0,0)))
                rest.append(p);uvs.append(tuple(uv));weights.append(1.);blink.append(delta);regions.append(side+1)
        for row in range(rows):
            for i in range(segments):
                k=base+row*segments+i;ni=base+row*segments+(i+1)%segments
                faces.extend([(k,ni+segments,ni),(k,k+segments,ni+segments)])
    mesh=bpy.data.meshes.new('LieOpenFaceSurface');mesh.from_pydata([blender(p) for p in rest],[],faces);mesh.update()
    face=bpy.data.objects.new('LieHumanOpenEyes',mesh);bpy.context.collection.objects.link(face)
    layer=mesh.uv_layers.new(name='CaptureUV')
    for poly in mesh.polygons:
        poly.use_smooth=True
        for loop in poly.loop_indices:layer.data[loop].uv=uvs[mesh.loops[loop].vertex_index]
    for mat in original.data.materials:mesh.materials.append(mat)
    face.shape_key_add(name='Basis');key=face.shape_key_add(name='blink')
    for i,p in enumerate(rest):key.data[i].co=blender(p+blink[i])
    for name,head in [('Neck',False),('Head',True)]:
        group=face.vertex_groups.new(name=name)
        for i,w in enumerate(weights):group.add([i],w if head else 1-w,'REPLACE')
    modifier=face.modifiers.new('LieInvisibleSkinning','ARMATURE');modifier.object=rig
    original.hide_render=True;original.hide_set(True)
    return face,rig,rest,weights,blink,uvs,color,normal,spec,anchors,regions,removed

def prepare_native_eyes(rig,anchors):
    result=[]
    source=eye()
    template=source.data.copy()
    for side,a in enumerate(anchors):
        obj=source if side==0 else bpy.data.objects.new('EyeRight',template.copy())
        if side:bpy.context.collection.objects.link(obj)
        obj.name='EyeLeft' if side==0 else 'EyeRight'
        # The reusable master is in Lie coordinates; Blender's authoring
        # basis is (x,-z,y), so transform source data once before attaching.
        for v in obj.data.vertices:v.co=blender(v.co)
        obj.location=blender(a);obj.shape_key_add(name='Basis')
        for name,radius in [('pupil_small',.0008),('pupil_large',.0032)]:
            key=obj.shape_key_add(name=name)
            for i,v in enumerate(obj.data.vertices):
                p=lie(v.co);r=math.hypot(p.x,p.y)
                if abs(p.z-.0103923)<2e-6 and r>1e-8:
                    nr=radius+(r-.0017)*(.006-radius)/(.006-.0017) if r>=.0017-1e-7 else r*radius/.0017
                    p.x*=nr/r;p.y*=nr/r
                key.data[i].co=blender(p)
        group=obj.vertex_groups.new(name='Head');group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
        modifier=obj.modifiers.new('LieHeadAttachment','ARMATURE');modifier.object=rig
        result.append(obj)
    bpy.data.meshes.remove(template)
    return result

def native_pose(face,rig,eyes,head,blink,yaw,pitch,pupil):
    face.data.shape_keys.key_blocks['blink'].value=blink
    bone=rig.pose.bones['Head'];bone.rotation_mode='XYZ';bone.rotation_euler=(0,math.radians(head),0)
    rotation=Matrix.Rotation(math.radians(yaw),4,'Z')@Matrix.Rotation(math.radians(pitch),4,'X')
    for obj in eyes:
        obj.rotation_mode='QUATERNION';obj.rotation_quaternion=rotation.to_quaternion()
        keys=obj.data.shape_keys.key_blocks
        keys['pupil_small'].value=max((.0017-pupil)/(.0017-.0008),0)
        keys['pupil_large'].value=max((pupil-.0017)/(.0032-.0017),0)
    bpy.context.view_layer.update()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resolution',type=int,default=384)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    if not 192<=args.resolution<=384:raise ValueError('Resolution outside capture budget')
    root=ROOT.parents[1]/'captures/face23';root.mkdir(parents=True,exist_ok=True)
    face,rig,rest,weights,blink,uvs,color,normal,spec,anchors,regions,removed=build_face()
    triangles,skin,views=capture(face,rest,uvs,color,normal,spec,root,args.resolution,native_tangents=True)
    for s in skin:s[15]=0. # material.w is now a region discriminator
    # Capture the same neutral eye master as LIE-22; keep one copy, invoke twice.
    eye_source=eye();eye_source.name='eye'
    fine,_,eye_metadata=capture_eye(eye_source,96,root)
    eye_triangles=[tuple(t.vertices) for t in eye_source.data.loop_triangles]
    eye_points=[v.co.copy() for v in eye_source.data.vertices]
    eye_bvh=BVHTree.FromPolygons(eye_points,eye_triangles,all_triangles=True)
    eye_probes=[]
    for i in range(0,len(fine),max(1,len(fine)//32)):
        s=fine[i];hit,_,ti,_=eye_bvh.find_nearest(Vector(s[:3]));tri=eye_triangles[ti]
        eye_probes.append({'sample':i,'triangle':tri,'bary':barycentric(hit,*(eye_points[k] for k in tri))})
        if len(eye_probes)==32:break
    eye_samples=[[*s[:3],-1.,*s[4:7],s[3],s[7],1.,1.,1.,s[10],.04,0.,s[8]+1.,*s[4:7],1.] for s in fine]
    bpy.data.objects.remove(eye_source,do_unlink=True)
    eyes=prepare_native_eyes(rig,anchors)
    probe_indices=list(range(0,len(skin),max(1,len(skin)//96)))[:96]
    lid_indices=[i for i,s in enumerate(skin) if any(regions[k]>0 for k in triangles[int(s[3])])]
    probe_indices+=lid_indices[::max(1,len(lid_indices)//64)][:64]
    cases=[]
    for head,bl,gaze_yaw,gaze_pitch,pupil in [(0,0,0,0,.0017),(0,.5,0,0,.0017),(0,1,0,0,.0017),(20,.3,25,-12,.0032),(-20,.7,-20,15,.0008)]:
        native_pose(face,rig,eyes,head,bl,gaze_yaw,gaze_pitch,pupil)
        deps=bpy.context.evaluated_depsgraph_get();evaluated=face.evaluated_get(deps);mesh=evaluated.to_mesh()
        points=[lie(evaluated.matrix_world@v.co) for v in mesh.vertices];positions=[]
        for i in probe_indices:
            s=skin[i];positions.append(list(sum((points[k]*w for k,w in zip(triangles[int(s[3])],s[:3])),Vector())))
        evaluated.to_mesh_clear();eye_positions=[]
        for obj in eyes:
            evaluated=obj.evaluated_get(deps);mesh=evaluated.to_mesh()
            points=[lie(evaluated.matrix_world@v.co) for v in mesh.vertices]
            eye_positions.append([list(sum((points[k]*w for k,w in zip(p['triangle'],p['bary'])),Vector())) for p in eye_probes])
            evaluated.to_mesh_clear()
        cases.append({'head_yaw':head,'blink':bl,'gaze_yaw':gaze_yaw,'gaze_pitch':gaze_pitch,'pupil_radius':pupil,'skin_positions':positions,'eye_positions':eye_positions})
    native_pose(face,rig,eyes,0,0,0,0,.0017)
    assets=ROOT.parent/'lie23';assets.mkdir(exist_ok=True)
    for image in bpy.data.images:
        if image.source=='FILE':image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(assets/'human-open-eyes.blend'))
    packets={'vertices.bin':b''.join(struct.pack('<12f',*p,w,*d,float(r),0,0,0,0) for p,w,d,r in zip(rest,weights,blink,regions)),
             'triangles.bin':b''.join(struct.pack('<4I',*t,0) for t in triangles),
             'samples.bin':b''.join(struct.pack('<20f',*s) for s in skin+eye_samples)}
    for name,data in packets.items():(root/name).write_bytes(data)
    manifest={'schema':1,'master_id':'lie-open-face23','capture_resolution':args.resolution,'capture_views':views,
        'sample_count':len(skin)+len(fine),'face_sample_count':len(skin),'eye_sample_count':len(fine),
        'invocation_count':len(skin)+2*len(fine),'vertex_count':len(rest),'triangle_count':len(triangles),
        'buffers':{n:{'bytes':len(d),'sha256':hashlib.sha256(d).hexdigest()} for n,d in packets.items()},
        'anchors':[list(a) for a in anchors],'eye_radius':RADIUS,'pivot':[0,.155,0],
        'source_author':'Lee Perry-Smith / Infinite-Realities','source_license':'CC-BY-3.0',
        'modifications':'Orbital openings, procedural blinking lids, reusable eyes, neutral material capture; original closed scan preserved hidden in .blend.',
        'removed_source_triangles':removed,'lid_sample_count':len(lid_indices),'original_mesh_drawn':False,
        'limits':['Artistic eyelid reconstruction; not a full anatomical face rig.','Wet-eye clearcoat approximation without corneal refraction.','Skin tint multiplies captured regional color; no melanin model.','No mouth interior, hair, eyelashes or complete facial expressions.']}
    assert manifest['invocation_count']<=1000000 and manifest['lid_sample_count']>100
    (root/'master.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (root/'native-oracle.json').write_text(json.dumps({'skin_probe_indices':probe_indices,'eye_probes':eye_probes,'cases':cases},indent=2)+'\n')
    print('LIE23 MASTER',json.dumps({k:manifest[k] for k in ['sample_count','face_sample_count','eye_sample_count','invocation_count','vertex_count','triangle_count','lid_sample_count','anchors']}),flush=True)

if __name__=='__main__':main()
