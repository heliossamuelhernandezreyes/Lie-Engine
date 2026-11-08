"""Dedicated multi-bank kernels with shared visibility and shading-only normals."""
import json
from pathlib import Path
from lie_scanned_masonry_shader import outputs as masonry_outputs
from lie_construction_reconstruction_shader import optimize
ROOT=Path(__file__).resolve().parents[1]
def outputs():
    original=masonry_outputs();result={};gd='extends RefCounted\nconst SHADERS={\n';bindings={8:[0,1,2,3,4,5,6,7,13,14,15,20],1:[4,5,6,7,13],2:[0,1,2,3,4,5,6,7,13,14,15,20],3:[0,1,2,3,4,5,6,7,13,14,15,20],4:[1,3,4,5,6,7,11,13,16,17,18,19],6:[1,3,4,5,6,7,8,9,11,13],7:[6,11,12]}
    for stage in (1,2,3,4,6,7,8):
        s=original[f'gpu_compute/shaders/lie_scanned_masonry_stage_{2 if stage==8 else stage}.glsl']
        if stage in (2,3,8):
            s=s.replace('layout(set=0,binding=0,std430)','layout(set=0,binding=14,std430) readonly buffer OpticalNormals {vec4 v[];} optical_normals;\nlayout(set=0,binding=0,std430)',1)
            s=s.replace('bool covered(Projection p,vec2 xy)', '''struct SourceBounds { uvec4 interval; vec4 low; vec4 high; };
layout(set=0,binding=15,std430) readonly buffer SourceLimits {SourceBounds v[];} source_limits;
bool in_source(uint sid,vec3 local) {
    uint lo=0u,hi=uint(parameters.iris.x);
    while(lo+1u<hi) {uint mid=(lo+hi)/2u;if(source_limits.v[mid].interval.x<=sid)lo=mid;else hi=mid;}
    SourceBounds b=source_limits.v[lo];
    return sid<b.interval.y && all(greaterThanEqual(local,b.low.xyz-vec3(.000002))) && all(lessThanEqual(local,b.high.xyz+vec3(.000002)));
}
bool covered(Projection p,vec2 xy)''')
            s=s.replace('if(inst.meta.z>0. && local.x>', 'if(!in_source(uint(p.gradient.w),local))return false;\n    if(inst.meta.z>0. && local.x>')
            s=s.replace('if(face_support && cut_support && z>', 'if(face_support && cut_support && in_source(sid,local_hit) && z>')
            s=s.replace('Sample s=samples.v[sid];Instance inst=instances.v[job.z];','Instance inst=instances.v[job.z];\n        if(int(inst.meta.y)!=int(parameters.settings.z))return;\n        Sample s=samples.v[sid];')
            s=s.replace('p.world=vec4(world,1);p.normal=vec4(n,front);','''vec3 shading=n;
            if(parameters.settings.w>.5) {vec4 optical=optical_normals.v[sid];if(optical.w>.5)shading=normalize(transpose(inverse(basis))*optical.xyz);}
            p.world=vec4(world,1);p.normal=vec4(shading,front);''')
        if stage==4:
            s=s.replace('vec3(.025)','vec3(.04)').replace('float nl=max(dot(n,l),0),nv=','float nl=dot(point.geometry.xyz,l)>0.?max(dot(n,l),0):0.,nv=')
        # World position is reconstructed from depth; its cached vec4 was unused.
        s=s.replace('struct Projection { vec4 world;', 'struct Projection {').replace('p.world=vec4(world,1);','')
        if stage==4:
            s=s.replace('layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;','').replace('layout(rgba32f,set=0,binding=9) uniform image2D specular_image;','')
            s=s.replace('imageStore(diffuse_image,xy,vec4(0));imageStore(specular_image,xy,vec4(0));','imageStore(output_image,xy,vec4(0));')
            s=s.replace('imageStore(diffuse_image,xy,vec4(irradiance,1));\n        imageStore(specular_image,xy,vec4(specular,1));return;', 'imageStore(output_image,xy,vec4(max(base*irradiance+specular,vec3(0)),1));return;')
            # Unreachable stage-6 text still has to parse without removed images.
            a=s.index('    if(stage==6) {');s=s[:a]+'\n}\n'
            shared=(ROOT/'gpu_compute/shaders/lib/lie_construction_field.glslinc').read_text()
            for marker,filename in [('STENCIL','lie_irradiance_stencil.glslinc'),('DIRECT','lie_surface_direct.glslinc'),('BRDF','lie_opaque_brdf.glslinc')]:shared=shared.replace('// SHARED_'+marker,(ROOT/'gpu_compute/shaders/lib'/filename).read_text())
            s=s.replace('void main() {',shared+'\nvoid main() {')
            s=s.replace('imageStore(output_image,xy,vec4(max(base*irradiance+specular,vec3(0)),1));',                'vec3 radiance=base*irradiance+specular;\n        if((field_map.config.z&1u)!=0u)radiance=construction_field_radiance(point,p,v,n,base,roughness,shadow_factor)+base*ambient*.96;\n        imageStore(output_image,xy,vec4(max(radiance,vec3(0)),1));')
        s=optimize(stage,s)
        path=f'shaders/lie_construction_scene_stage_{stage}.glsl' ;result['gpu_compute/'+path]=s;gd+=f'    {stage}:preload("res://{path}"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':')).replace('"','')+'\n';result['gpu_compute/lie_construction_scene_kernels.gd']=gd;return result
if __name__=='__main__':
    for path,data in outputs().items():(ROOT/path).write_text(data)
