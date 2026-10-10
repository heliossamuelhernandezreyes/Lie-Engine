"""A captured, surface-bound human master with a native editable Blender rig.

Camera rays capture neutral grayscale/filter/normal/depth. A stable triangle
and barycentric binding attaches each image sample to invisible deforming data.
Source triangles are never a runtime drawing primitive. This first scan has
closed eyes: lid_squeeze and jaw_drop are authored stress correctives, not a
complete anatomical face rig or a photoreal open mouth.
"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lie20_source import ROOT, acquire, read_mesh


def smooth(a, b, value):
    t = min(max((value-a)/(b-a), 0), 1)
    return t*t*(3-2*t)


def blender(p):
    return Vector((p[0], -p[2], p[1]))


def lie(p):
    return Vector((p.x, p.z, -p.y))


def barycentric(p, a, b, c):
    e, f, q = b-a, c-a, p-a
    ee, ef, ff, qe, qf = e.dot(e), e.dot(f), f.dot(f), q.dot(e), q.dot(f)
    det = ee*ff-ef*ef
    if det < 1e-18:
        return None
    y, z = (ff*qe-ef*qf)/det, (ee*qf-ef*qe)/det
    return (1-y-z, y, z)


def srgb(value):
    return value/12.92 if value <= .04045 else ((value+.055)/1.055)**2.4


class Texture:
    def __init__(self, name):
        self.image = bpy.data.images.load(str(ROOT/name), check_existing=False)
        self.image.colorspace_settings.name = 'Non-Color'
        if max(self.image.size) > 1024:
            self.image.scale(1024, 1024)
        self.width, self.height = self.image.size
        self.pixels = array('f', [0])*(self.width*self.height*4)
        self.image.pixels.foreach_get(self.pixels)

    def at(self, uv):
        x = min(max(uv.x*self.width-.5, 0), self.width-1)
        y = min(max(uv.y*self.height-.5, 0), self.height-1)
        ix, iy = int(x), int(y)
        nx, ny = min(ix+1, self.width-1), min(iy+1, self.height-1)
        tx, ty = x-ix, y-iy
        weights = ((ix, iy, (1-tx)*(1-ty)), (nx, iy, tx*(1-ty)),
                   (ix, ny, (1-tx)*ty), (nx, ny, tx*ty))
        return Vector(tuple(sum(self.pixels[(yy*self.width+xx)*4+k]*w for xx, yy, w in weights) for k in range(3)))


def author():
    acquire()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    points, normals, texcoords, faces = read_mesh(ROOT/'LeePerrySmith.glb')
    bottom = min(p[1] for p in points)
    scale = .42/(max(p[1] for p in points)-bottom)
    rest = [Vector((p[0]*scale, (p[1]-bottom)*scale, p[2]*scale)) for p in points]
    mesh = bpy.data.meshes.new('LieHumanReferenceSurface')
    mesh.from_pydata([blender(p) for p in rest], [], faces)
    mesh.update()
    obj = bpy.data.objects.new('LieHumanMaster_LeePerrySmith', mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    layer = mesh.uv_layers.new(name='CaptureUV')
    # This particular legacy scan uses its original UVs with TextureLoader's
    # vertical convention. It must NOT be treated as an arbitrary glTF texture.
    for poly in mesh.polygons:
        poly.use_smooth = True
        for loop in poly.loop_indices:
            layer.data[loop].uv = texcoords[mesh.loops[loop].vertex_index]
    weights, lid, jaw = [], [], []
    obj.shape_key_add(name='Basis')
    lid_key = obj.shape_key_add(name='lid_squeeze')
    jaw_key = obj.shape_key_add(name='jaw_drop')
    for i, p in enumerate(rest):
        weights.append(smooth(.105, .195, p.y))
        eye = math.exp(-((abs(p.x)-.043)/.016)**2-((p.y-.294)/.012)**2)*smooth(.035, .085, p.z)
        lid.append(Vector((0, -.0025*eye, .0008*eye)))
        lower = (1-smooth(.225, .245, p.y))*smooth(.17, .195, p.y)*math.exp(-(p.x/.065)**6)*smooth(.02, .08, p.z)
        jaw.append(Vector((0, -.012*lower, .003*lower)))
        lid_key.data[i].co = blender(p+lid[-1])
        jaw_key.data[i].co = blender(p+jaw[-1])
    root_group = obj.vertex_groups.new(name='Neck')
    head_group = obj.vertex_groups.new(name='Head')
    for i, w in enumerate(weights):
        root_group.add([i], 1-w, 'REPLACE')
        head_group.add([i], w, 'REPLACE')
    rig_data = bpy.data.armatures.new('LieInvisibleRig')
    rig = bpy.data.objects.new('LieInvisibleRig', rig_data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    obj.select_set(False)
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    neck = rig_data.edit_bones.new('Neck'); neck.head=(0, 0, 0); neck.tail=(0, 0, .155)
    head = rig_data.edit_bones.new('Head'); head.head=(0, 0, .155); head.tail=(0, 0, .24); head.parent=neck
    bpy.ops.object.mode_set(mode='OBJECT')
    modifier = obj.modifiers.new('LieInvisibleSkinning', 'ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = False
    color, normal, spec = Texture('Map-COL.jpg'), Texture('Infinite-Level_02_Tangent_SmoothUV.jpg'), Texture('Map-SPEC.jpg')
    material = bpy.data.materials.new('LieSkinReference'); material.use_nodes=True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    bsdf = nodes.get('Principled BSDF'); bsdf.inputs['Roughness'].default_value=.45
    bsdf.inputs['Subsurface Weight'].default_value=.25
    bsdf.inputs['Subsurface Radius'].default_value=(.006, .003, .0015)
    for texture, socket in [(color, 'Base Color')]:
        texture.image.colorspace_settings.name='sRGB'
        node=nodes.new('ShaderNodeTexImage'); node.image=texture.image
        links.new(node.outputs['Color'],bsdf.inputs[socket])
    node=nodes.new('ShaderNodeTexImage'); node.image=normal.image
    nmap=nodes.new('ShaderNodeNormalMap'); nmap.inputs['Strength'].default_value=.65
    links.new(node.outputs['Color'],nmap.inputs['Color']);links.new(nmap.outputs['Normal'],bsdf.inputs['Normal'])
    snode=nodes.new('ShaderNodeTexImage');snode.image=spec.image
    rough=nodes.new('ShaderNodeMapRange');rough.inputs['From Min'].default_value=0;rough.inputs['From Max'].default_value=1
    rough.inputs['To Min'].default_value=.62;rough.inputs['To Max'].default_value=.27
    links.new(snode.outputs['Color'],rough.inputs['Value']);links.new(rough.outputs['Result'],bsdf.inputs['Roughness'])
    mesh.materials.append(material)
    return obj, rig, rest, weights, lid, jaw, texcoords, color, normal, spec


def save_image(path, values, resolution, bits=16):
    image=bpy.data.images.new(path.stem,width=resolution,height=resolution,alpha=True,float_buffer=True)
    image.colorspace_settings.name='Non-Color';image.pixels.foreach_set(values)
    image.filepath_raw=str(path);image.file_format='PNG'
    scene=bpy.context.scene;scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth=str(bits)
    temporary=path.with_name(path.stem+'.writing.png')
    for attempt in range(3):
        image.save_render(str(temporary), scene=scene)
        data=temporary.read_bytes();offset=8;complete=data.startswith(b'\x89PNG\r\n\x1a\n')
        while complete and offset+12<=len(data):
            size=struct.unpack_from('>I',data,offset)[0];end=offset+size+12
            if end>len(data):complete=False;break
            payload=data[offset+4:end-4]
            if zlib.crc32(payload)!=struct.unpack_from('>I',data,end-4)[0]:complete=False;break
            offset=end
            if payload[:4]==b'IEND':break
        if complete and offset==len(data) and data[-12:]==b'\x00\x00\x00\x00IEND\xaeB\x60\x82':
            temporary.replace(path);break
    else:raise RuntimeError('Incomplete PNG capture: '+str(path))
    bpy.data.images.remove(image)


def capture(obj, rest, uvs, color, normal, spec, root, resolution, native_tangents=False, angles=None):
    bpy.context.scene.view_settings.view_transform='Raw'
    mesh=obj.data;mesh.calc_loop_triangles()
    triangles=[tuple(t.vertices) for t in mesh.loop_triangles]
    loop_frames=[]
    if native_tangents:
        mesh.calc_tangents(uvmap='CaptureUV')
        loop_frames=[[(lie(mesh.loops[k].tangent),mesh.loops[k].bitangent_sign) for k in t.loops] for t in mesh.loop_triangles]
    bvh=BVHTree.FromPolygons(rest,triangles,all_triangles=True)
    ns=[lie(v.normal) for v in mesh.vertices]
    center=Vector((0,.21,0));scale=.52;step=scale/resolution;grid=step*.65
    samples={};views=[]
    for elevation in [-45,0,45]:
        for azimuth in range(0,360,30):
            if angles is not None and (azimuth,elevation) not in angles:continue
            az,el=math.radians(azimuth),math.radians(elevation)
            direction=Vector((math.sin(az)*math.cos(el),math.sin(el),math.cos(az)*math.cos(el)))
            right=Vector((math.cos(az),0,-math.sin(az)));up=direction.cross(right).normalized()
            origin=center+direction*.9
            channels={key:array('f',[0])*(resolution*resolution*4) for key in ['gray','filter','normal','depth']}
            valid=0
            for y in range(resolution):
                for x in range(resolution):
                    ray=origin+right*((x+.5)/resolution-.5)*scale+up*((y+.5)/resolution-.5)*scale
                    hit, face_normal, ti, distance=bvh.ray_cast(ray,-direction,2)
                    if hit is None: continue
                    indices=triangles[ti];a,b,c=[rest[k] for k in indices]
                    bary=barycentric(hit,a,b,c)
                    if bary is None or min(bary)<-1e-4: continue
                    n=sum((ns[k]*w for k,w in zip(indices,bary)),Vector()).normalized()
                    front=n.dot(direction)
                    uv=sum((Vector(uvs[k])*w for k,w in zip(indices,bary)),Vector((0,0)))
                    rgb=Vector(tuple(srgb(v) for v in color.at(uv)))
                    gray=max(rgb);tint=rgb/max(gray,1e-8)
                    du1,du2=Vector(uvs[indices[1]])-Vector(uvs[indices[0]]),Vector(uvs[indices[2]])-Vector(uvs[indices[0]])
                    determinant=du1.x*du2.y-du1.y*du2.x
                    shading=n.copy()
                    if native_tangents:
                        frame=loop_frames[ti]
                        tangent=sum((t*w for (t,sign),w in zip(frame,bary)),Vector())
                        tangent=(tangent-n*tangent.dot(n)).normalized()
                        sign=sum(sign*w for (t,sign),w in zip(frame,bary))
                        bitangent=n.cross(tangent)*(1 if sign>=0 else -1)
                        tex=normal.at(uv)*2-Vector((1,1,1));tex.x*=.65;tex.y*=.65;tex.z=.35+.65*tex.z
                        shading=(tangent*tex.x+bitangent*tex.y+n*tex.z).normalized()
                    elif abs(determinant)>1e-12:
                        tangent=((b-a)*du2.y-(c-a)*du1.y)/determinant
                        tangent=(tangent-n*tangent.dot(n)).normalized()
                        bitangent=n.cross(tangent)*(1 if determinant>0 else -1)
                        tex=normal.at(uv)*2-Vector((1,1,1));tex.x*=.65;tex.y*=.65
                        shading=(tangent*tex.x+bitangent*tex.y+n*tex.z).normalized()
                    roughness=.62-.35*sum(spec.at(uv))/3
                    index=((resolution-1-y)*resolution+x)*4
                    for key,value in [('gray',(*([gray]*3),1)),('filter',(*tint,1)),('normal',(*(shading*.5+Vector((.5,.5,.5))),1)),('depth',(*([distance/2]*3),1))]:
                        channels[key][index:index+4]=array('f',value)
                    valid+=1
                    if front<.3: continue
                    key=tuple(round(v/grid) for v in hit)+tuple(round(v*3) for v in n)
                    old=samples.get(key)
                    if old is None or front>old[0]:
                        samples[key]=(front,[*bary,float(ti),*shading,step*.72/math.sqrt(front),gray,*tint,roughness,.04,.25,.006,*n,front])
            code=f'az{azimuth:03d}_el{elevation:+03d}'
            for key,values in channels.items():save_image(root/f'{code}.{key}.png',values,resolution)
            views.append({'azimuth':azimuth,'elevation':elevation,'direction':list(direction),'right':list(right),'up':list(up),'origin':list(origin),'valid_pixels':valid,'code':code})
            print('LIE20 CAPTURE',code,valid,'pixels',len(samples),'canonical samples',flush=True)
    ordered=[value[1] for _,value in sorted(samples.items())]
    return triangles,ordered,views


def pose(obj, rig, head, lid, jaw):
    obj.data.shape_keys.key_blocks['lid_squeeze'].value=lid
    obj.data.shape_keys.key_blocks['jaw_drop'].value=jaw
    bone=rig.pose.bones['Head'];bone.rotation_mode='XYZ';bone.rotation_euler=(0,math.radians(head),0)
    bpy.context.view_layer.update()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resolution',type=int,default=192);parser.add_argument('--no-reference',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    root=ROOT.parents[1]/'captures/human_master';root.mkdir(parents=True,exist_ok=True)
    obj,rig,rest,weights,lid,jaw,uvs,color,normal,spec=author()
    triangles,samples,views=capture(obj,rest,uvs,color,normal,spec,root,args.resolution)
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
    source_path=ROOT/'human-master.blend'
    for image in bpy.data.images:
        if image.source=='FILE':image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    manifest={'schema':1,'master_id':'lie-human-lee-perry-smith-v1','capture_resolution':args.resolution,'capture_views':views,
        'sample_count':len(samples),'vertex_count':len(rest),'triangle_count':len(triangles),'strides':{'sample':80,'vertex':48,'triangle':16},
        'buffers':{name:{'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in packets.items()},
        'pivot':[0,.155,0],'target':[0,.23,0],'orthographic_scale':.52,'normal_space':'Lie object XYZ','gray_filter_color_space':'linear RGB',
        'source_lock':'../../assets/lie20/source-lock.json','original_mesh_drawn':False,
        'shape_keys':['lid_squeeze','jaw_drop'],'limitations':['Closed-eye scan; no eyeballs, cornea, hair or mouth interior.','Correctives are experimental authored offsets; not anatomical expressions.','Specular scan converted to an artistic roughness approximation.','Human indirect illumination and complete shadow transport are not implemented.']}
    (root/'master.json').write_text(json.dumps(manifest,indent=2)+'\n')
    if not args.no_reference:
        from lie20_reference_blender import render_references
        render_references(obj,rig,root,pose)
    print('LIE20 MASTER',len(samples),'samples',len(rest),'invisible vertices',flush=True)


if __name__=='__main__':main()
