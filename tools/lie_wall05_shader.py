"""Generate the opt-in shared/cached compositor from the locked WALL04 shader.

Preserves the original footprint, depth and photographic recovery equations.
Adds source-ID indirection, geometry-only recovery coefficients and resampling.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def replace(s,old,new):
    if old not in s:raise ValueError('WALL04 shader contract changed: '+old[:80])
    return s.replace(old,new)

def generate():
    s=(ROOT/'gpu_compute/shaders/lie_wall04_mortar.glsl').read_text()
    s=replace(s,'layout(push_constant,std430) uniform Phase',r'''
layout(set=0,binding=17,std430) readonly buffer SampleReferences { uint values[]; } sample_refs;
layout(set=0,binding=18,std430) buffer RecoveryMap { uint values[]; } recovery_map;
struct Recovery { uvec4 info; vec4 coefficients[9]; };
layout(set=0,binding=19,std430) buffer RecoveryRecords { Recovery values[]; } recovery;
layout(set=0,binding=20,std430) buffer RecoveryCount { uint count; uint overflow; uint reserved_a; uint reserved_b; } recovery_count;
const uint MAX_RECOVERY=65536u;
// A virtual sample is reconstructed from ONE original immutable brick master.
// Per-instance transforms, source subset IDs and tint recreate the old WALL04
// records; photo mortar records are copied unchanged. No original mesh draws.
Sample fetch_sample(uint sid, Instance inst) {
    Sample s=samples.v[sid];
    uint brick=uint(inst.meta.x)/128u;
    if(brick<96u) {
        vec3 n=s.normal_gray.xyz,p=s.position_radius.xyz;
        vec3 an=abs(n);
        uint patch=an.x>=an.y && an.x>=an.z ? (n.x>=0?0u:1u) :
                   an.y>=an.z ? (n.y>=0?2u:3u) :
                   n.z<0?4u:5u+uint(p.x>=0)+2u*uint(p.y>=0);
        mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);
        p=basis*p+inst.origin.xyz;n=basis*n;
        s.position_radius=vec4(p,max(s.position_radius.w,inst.meta.z));
        s.normal_gray.xyz=n;s.attributes.y=float(brick*9u+patch);s.attributes.w=0.;
        s.albedo.rgb=clamp(s.albedo.rgb*inst.tint.rgb,vec3(0),vec3(1));
        an=abs(n);vec2 q=an.x>=an.y && an.x>=an.z?p.zy:an.y>=an.z?p.xz:p.xy;
        float r=2.*s.position_radius.w;s.support=vec4(q-r,q+r);
    }
    return s;
}
Instance render_instance(Instance inst) {
    inst.x=vec4(1,0,0,0);inst.y=vec4(0,1,0,0);inst.z=vec4(0,0,1,0);
    inst.origin=vec4(0);inst.tint.rgb=vec3(1);return inst;
}
uint projection_node(Projection p) {
    return uint(round(fetch_sample(uint(p.gradient.w),instances.v[uint(p.gradient.z)]).attributes.y));
}
layout(push_constant,std430) uniform Phase''')
    s=replace(s,'Sample s=samples.v[uint(p.gradient.w)];\n    Instance inst=instances.v[uint(p.gradient.z)];',
      'Instance source_inst=instances.v[uint(p.gradient.z)];\n    Sample s=fetch_sample(uint(p.gradient.w),source_inst);\n    Instance inst=render_instance(source_inst);')
    s=replace(s,'uint sid=job.x+i-job.w;\n        Sample s=samples.v[sid];Instance inst=instances.v[job.z];',
      'uint sid=sample_refs.values[job.x+i-job.w];\n        Instance source_inst=instances.v[job.z];Sample s=fetch_sample(sid,source_inst);Instance inst=render_instance(source_inst);')
    s=replace(s,'uint node=uint(max(round(samples.v[sid].attributes.y),0.0));','uint node=projection_node(pr);')
    s=replace(s,'Sample surf=samples.v[sid];','Sample surf=fetch_sample(sid,instances.v[uint(point.gradient.z)]);')
    s=replace(s,'if(i<pixels) {depths.v[i]', 'if(i==0u) {recovery_count.count=0u;recovery_count.overflow=0u;}\n        if(i<pixels) {recovery_map.values[i]=0u;depths.v[i]')
    s=replace(s,'if(stage==8) {','if(stage==8 || stage==9) {')
    s=replace(s,'        // Geometry-independent mortar joint coverage',r'''        // Re-light already validated holes without searching source neighborhoods.
        if(stage==9 && recovery_map.values[i]!=EMPTY) {
            uint slot=recovery_map.values[i];
            if(slot==0u) {imageStore(specular_image,q,base);return;}
            Recovery record=recovery.values[slot-1u];
            vec3 rgb=vec3(0);uint node_base=record.info.x;
            for(uint k=0u;k<record.info.y;k++) {
                uint node=node_base+k;
                vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(node),0)).rgb,vec3(0));
                float absorption=clamp(injected_material_codes.values[node*3u+2u].w,0.,1.);
                rgb+=record.coefficients[k].rgb*E*(1.-absorption);
            }
            imageStore(specular_image,q,vec4(max(rgb,vec3(0)),1));return;
        }
        // Overflow deliberately falls back to the original photographic search.
        // Geometry-independent mortar joint coverage''')
    s=replace(s,'        vec3 color_sum=vec3(0.);','        vec3 color_sum=vec3(0.);\n        vec3 coeff[9];for(int k=0;k<9;k++)coeff[k]=vec3(0);\n        uint node_base=chosen_group<96u?chosen_group*9u:864u+chosen_group-96u;')
    s=replace(s,'            color_sum+=v.rgb*weight;sum+=weight;',r'''            color_sum+=v.rgb*weight;sum+=weight;
            Accumulator acc=accumulated.v[ix];
            vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);
            coeff[node-node_base]+=albedo*(weight/PI);''')
    s=replace(s,'            imageStore(specular_image,q,vec4(color_sum/sum,1.));',r'''            imageStore(specular_image,q,vec4(color_sum/sum,1.));
            if(stage==8) {
                uint slot=atomicAdd(recovery_count.count,1u);
                if(slot<MAX_RECOVERY) {
                    Recovery r;r.info=uvec4(node_base,chosen_group<96u?9u:1u,0,0);
                    for(int k=0;k<9;k++)r.coefficients[k]=vec4(coeff[k]/sum,0);
                    recovery.values[slot]=r;recovery_map.values[i]=slot+1u;
                } else {recovery_map.values[i]=EMPTY;atomicAdd(recovery_count.overflow,1u);}
            }''')
    s=replace(s,'        for(int y=0;y<scale;y++) for(int x=0;x<scale;x++) {\n            vec4 value=imageLoad(specular_image,xy*scale+ivec2(x,y));linear+=value.rgb*value.a;coverage+=value.a;\n        }',r'''        float ratio=float(parameters.counts.z)/float(size.x);
        vec2 low=vec2(xy)*ratio, high=low+vec2(ratio);
        ivec2 begin=ivec2(floor(low)),end=ivec2(ceil(high));
        for(int y=begin.y;y<end.y;y++) for(int x=begin.x;x<end.x;x++) {
            vec2 overlap=max(vec2(0),min(vec2(x,y)+1.,high)-max(vec2(x,y),low));
            float weight=overlap.x*overlap.y;
            vec4 value=imageLoad(specular_image,ivec2(x,y));linear+=value.rgb*(value.a*weight);coverage+=value.a*weight;
        }''')
    s=replace(s,'coverage/float(scale*scale)','coverage/(ratio*ratio)')
    return s
if __name__=='__main__':
    (ROOT/'gpu_compute/shaders/lie_wall05_shared_cached.glsl').write_text(generate())
