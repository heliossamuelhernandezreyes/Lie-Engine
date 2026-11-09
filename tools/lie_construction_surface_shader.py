"""Camera-only disk conics, bounded cooperative work and stable material owner.

The old 6.4 kernels are generated separately as an explicit A/B reference.
All captures, source support, shadows and 64-byte projection storage survive.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]

def replace_function(shader,name,replacement):
    match=re.search(r'\b(?:float|bool|ivec2)\s+'+name+r'\([^\n]*\)\s*\{',shader)
    if match is None:raise ValueError('missing surface function '+name)
    at=shader.index('{',match.start());depth=1;end=at+1
    while depth:
        depth+=(shader[end]=='{')-(shader[end]=='}');end+=1
    return shader[:match.start()]+replacement+shader[end:]

DEPTH='''float pixel_depth(Projection p,vec2 xy) {
    if(p.radius<0.) {
        vec2 uv=xy/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)
            +parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
        return p.depth/dot(p.geometry,ray);
    }
    return 1.0/(1.0/p.depth+dot(p.gradient,xy-p.center));
}'''
DISTANCE='''float footprint_distance(Projection p,vec2 xy) {
    if(p.radius<0.) {
        float z=pixel_depth(p,xy);
        if(isnan(z)||isinf(z)||z<=parameters.lens.z||z>=parameters.lens.w)return 2.;
        vec2 uv=xy/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)
            +parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
        vec3 d=ray*z-p.ellipse;return dot(d,d)/(p.radius*p.radius);
    }
    vec2 q=xy-p.center;
    return q.x*q.x*p.ellipse.x+2.*q.x*q.y*p.ellipse.y+q.y*q.y*p.ellipse.z;
}'''

SMALL=r'''
void main() {
    uint invocation=gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x;
    if(invocation>=uint(parameters.counts.x))return;
    uint j=job_index(invocation);uvec4 address=bank_jobs.v[j];uint local_index=invocation-address.x;
    uint i=address.y+local_index;
    if(address.w!=0u) {uint cursor=address.y+local_index;i=bank_jobs.v[cursor/4u][cursor%4u];}
    uvec4 job=jobs.v[address.z];uint sid=job.x+i-job.w;
    Instance inst=instances.v[job.z];if(int(inst.meta.y)!=int(parameters.settings.z))return;
    Sample s=samples.v[sid];
    mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz),inverse_basis=inverse(basis);
    SourceBounds bounds=source_bounds(sid);Projection p;
    const int stage=STAGE;
    if(stage==2) {
        vec3 local=s.position_radius.xyz;float radius=s.position_radius.w;
        if(parameters.settings.y<.5) {
            float r=length(local.xy),inner=.0017,outer=.006;
            if(int(s.attributes.x)==1 && r>1e-8) {
                float nr=parameters.iris.w+(r-inner)*(outer-parameters.iris.w)/(outer-inner);
                local.xy*=nr/r;radius*=max(nr/r,(outer-parameters.iris.w)/(outer-inner));
            } else if(int(s.attributes.x)==2) {local.xy*=parameters.iris.w/inner;radius*=parameters.iris.w/inner;}
        }
        vec3 delta=basis*local+inst.origin.xyz-parameters.eye.xyz;
        vec3 n=normalize(transpose(inverse_basis)*s.normal_gray.xyz),shading=n;
        if(parameters.settings.w>.5) {vec4 optical=optical_normals.v[sid];if(optical.w>.5)shading=normalize(transpose(inverse_basis)*optical.xyz);}
        radius*=max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
        p=lie_project_surface(delta,n,shading,radius,float(job.z));projected.v[i]=p;
    } else p=projected.v[i];
    if(p.radius==0.)return;
    ivec4 box=lie_surface_bounds(p);if(lie_empty_bounds(box))return;
    if(lie_large_surface(p,box)) {if(stage==2)lie_enqueue(i,address.z);return;}
    LIE_PROBE_DECLARE;
    for(int y=box.y;y<=box.w;y++) {
        ivec2 row=lie_surface_row(p,box,y);
        for(int x=row.x;x<=row.y;x++) {
            vec2 xy=vec2(x,y)+.5;float distance=footprint_distance(p,xy);
            if(distance>1. || !lie_finite(distance))continue;
            float z=pixel_depth(p,xy);if(z<=parameters.lens.z||z>=parameters.lens.w||!lie_finite(z))continue;
            uint pixel=uint(y*parameters.counts.z+x),bits=floatBitsToUint(z);
            if(stage==3 && depths.v[pixel]!=bits)continue;
            if(stage==12) {
                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;
                uint winner=winners.v[pixel];if(winner==EMPTY||projected.v[winner].owner!=p.owner)continue;
            }
            if(stage==2) {LIE_PROBE_TEST;}
            if(!covered(p,xy,s,inst,inverse_basis,bounds,sid))continue;
            if(stage==2) {LIE_PROBE_SUPPORT;atomicMin(depths.v[pixel],bits);}
            else if(stage==3)atomicMin(winners.v[pixel],i);
            else {lie_accumulate(pixel,i,p,s,inst,distance);LIE_PROBE_ACCEPT;}
        }
    }
    if(stage==2) {LIE_PROBE_DEPTH;}
    if(stage==12) {LIE_PROBE_MATERIAL;}
}
'''

LARGE=r'''
shared ivec4 lie_large_box;
void main() {
    uint h=lie_queue_header(),group=gl_WorkGroupID.x+gl_WorkGroupID.y*gl_NumWorkGroups.x;
    if(group>=bank_jobs.v[h].w)return;
    uint at=(h+2u)*4u+group*2u;
    uint i=bank_jobs.v[at/4u][at%4u],j=bank_jobs.v[(at+1u)/4u][(at+1u)%4u];
    uvec4 job=jobs.v[j];uint sid=job.x+i-job.w;
    Instance inst=instances.v[job.z];if(int(inst.meta.y)!=int(parameters.settings.z))return;
    Sample s=samples.v[sid];Projection p=projected.v[i];
    mat3 inverse_basis=inverse(mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz));
    SourceBounds bounds=source_bounds(sid);
    if(gl_LocalInvocationID.x==0u)lie_large_box=lie_supported_bounds(p,s,inst,bounds);
    barrier();ivec4 box=lie_large_box;
    if(lie_empty_bounds(box))return;
    uint width=uint(box.z-box.x+1),height=uint(box.w-box.y+1);
    LIE_PROBE_DECLARE;int stage=phase.value.x;
    // A complete footprint is processed in bounded viewport work distributed
    // over 64 lanes. No fixed source list cap and no per-tile dropping.
    for(uint k=gl_LocalInvocationID.x;k<width*height;k+=64u) {
        ivec2 q=box.xy+ivec2(int(k%width),int(k/width));vec2 xy=vec2(q)+.5;
        float distance=footprint_distance(p,xy);if(distance>1. || !lie_finite(distance))continue;
        float z=pixel_depth(p,xy);if(z<=parameters.lens.z||z>=parameters.lens.w||!lie_finite(z))continue;
        uint pixel=uint(q.y*parameters.counts.z+q.x),bits=floatBitsToUint(z);
        if(stage==10 && depths.v[pixel]!=bits)continue;
        if(stage==11) {
            if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;
            uint winner=winners.v[pixel];if(winner==EMPTY||projected.v[winner].owner!=p.owner)continue;
        }
        if(stage==9) {LIE_PROBE_TEST;}
        if(!covered(p,xy,s,inst,inverse_basis,bounds,sid))continue;
        if(stage==9) {LIE_PROBE_SUPPORT;atomicMin(depths.v[pixel],bits);}
        else if(stage==10)atomicMin(winners.v[pixel],i);
        else {lie_accumulate(pixel,i,p,s,inst,distance);LIE_PROBE_ACCEPT;}
    }
    if(stage==9) {LIE_PROBE_DEPTH;}
    if(stage==11) {LIE_PROBE_MATERIAL;}
}
'''

def camera_shader(stage,original):
    prefix=original[:original.index('void main() {')]
    prefix=prefix.replace('readonly buffer BankJobs','buffer BankJobs')
    prefix=replace_function(prefix,'pixel_depth',DEPTH)
    prefix=replace_function(prefix,'footprint_distance',DISTANCE)
    prefix=replace_function(prefix,'lie_splat_row','')
    lib=(ROOT/'gpu_compute/shaders/lib/lie_construction_surface.glslinc').read_text()
    return prefix+'\n'+lib+'\n'+(LARGE if stage==9 else SMALL.replace('STAGE',str(stage)))
