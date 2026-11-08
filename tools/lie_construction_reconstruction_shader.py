"""Exact-work construction rasterization; source support remains authoritative.

Keep global sample/owner addresses while dispatching only each bank's jobs.
Separate light visibility from camera visibility, bound the SAME ellipse by
rows, and reject hidden accumulation candidates before source-space tests.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def optimize(stage, shader):
    if stage == 1:
        return shader.replace('if(i<pixels) {', 'if(phase.value.z!=0 && i<pixels) {').replace(
            'if(i<uint(SHADOW_SIZE*SHADOW_SIZE))',
            'if(phase.value.w!=0 && i<uint(SHADOW_SIZE*SHADOW_SIZE))')
    if stage not in (2, 3, 8):
        return shader

    shader = shader.replace('uint job_index(uint invocation) {',
        'layout(set=0,binding=20,std430) readonly buffer BankJobs {uvec4 v[];} bank_jobs;\nuint job_index(uint invocation) {')
    shader = shader.replace('jobs.v[mid].w<=invocation', 'bank_jobs.v[mid].x<=invocation')
    shader = shader.replace('uint j=job_index(i);uvec4 job=jobs.v[j];uint sid=job.x+i-job.w;',
        'uint j=job_index(i);uvec4 address=bank_jobs.v[j];uint local_index=i-address.x;\n'
        '        if(address.w==0u)i=address.y+local_index;\n'
        '        else {uint cursor=address.y+local_index;i=bank_jobs.v[cursor/4u][cursor%4u];}\n'
        '        uvec4 job=jobs.v[address.z];uint sid=job.x+i-job.w;')

    # Resolve the immutable source interval once per sample, not per pixel.
    shader = shader.replace('bool in_source(uint sid,vec3 local) {',
                            'SourceBounds source_bounds(uint sid) {')
    shader = shader.replace('    SourceBounds b=source_limits.v[lo];\n    return sid<b.interval.y && ',
        '    return source_limits.v[lo];\n}\n'
        'bool in_source(SourceBounds b,uint sid,vec3 local) {\n    return sid<b.interval.y && ')
    shader = shader.replace('bool covered(Projection p,vec2 xy) {',
        'bool covered(Projection p,vec2 xy,Sample s,Instance inst,mat3 inverse_basis,SourceBounds bounds) {')
    shader = shader.replace('    Sample s=samples.v[uint(p.gradient.w)];\n    Instance inst=instances.v[uint(p.gradient.z)];\n', '')
    shader = shader.replace('inverse(mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz))*', 'inverse_basis*')
    shader = shader.replace('in_source(uint(p.gradient.w),local)', 'in_source(bounds,uint(p.gradient.w),local)')
    shader = shader.replace('in_source(sid,local_hit)', 'in_source(bounds,sid,local_hit)')
    shader = shader.replace('mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);',
        'mat3 basis=mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz);\n'
        '        mat3 inverse_basis=inverse(basis);SourceBounds bounds=source_bounds(sid);')
    shader = shader.replace('transpose(inverse(basis))', 'transpose(inverse_basis)').replace('inverse(basis)*', 'inverse_basis*')

    shadow_start = shader.index('            vec3 ld=world-parameters.light.xyz;')
    shadow_end = shader.index('            if(depth>parameters.lens.z', shadow_start)
    shadow = shader[shadow_start:shadow_end]
    # Restrict candidates to the same original square and viewport. All source,
    # cut, radius and depth predicates below are retained, including borders.
    shadow = shadow.replace(
        'for(int y=-shadow_bound;y<=shadow_bound;y++)for(int x=-shadow_bound;x<=shadow_bound;x++) {\n'
        '                    ivec2 q=ivec2(xy)+ivec2(x,y);',
        'ivec2 center=ivec2(xy);\n'
        '                for(int y=max(-shadow_bound,-center.y);y<=min(shadow_bound,SHADOW_SIZE-1-center.y);y++)\n'
        '                for(int x=max(-shadow_bound,-center.x);x<=min(shadow_bound,SHADOW_SIZE-1-center.x);x++) {\n'
        '                    ivec2 q=center+ivec2(x,y);')
    if stage == 8:
        # This pass has no camera dependency. Disabling display of shadows does
        # not destroy the resident light-depth map or change its geometry.
        prefix = shader[:shader.index('void main() {')]
        lookup_start = shader.index('        if(i>=uint(parameters.counts.x))return;')
        lookup_end = shader.index('        Projection p;', lookup_start)
        lookup = shader[lookup_start:lookup_end]
        return prefix + '''void main() {
    uint i=gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x;
''' + lookup + '''
        vec3 world=basis*s.position_radius.xyz+inst.origin.xyz;
        vec3 n=normalize(transpose(inverse_basis)*s.normal_gray.xyz);
        float radius=s.position_radius.w*max(length(inst.x.xyz),max(length(inst.y.xyz),length(inst.z.xyz)));
''' + shadow + '\n}\n'
    shader = shader[:shadow_start] + shader[shadow_end:]
    helper = (ROOT / 'gpu_compute/shaders/lib/lie_splat_work.glslinc').read_text()
    shader = shader.replace('void main() {', helper + '\nvoid main() {')
    shader = shader.replace(
        'for(int y=-bound;y<=bound;y++)for(int x=-bound;x<=bound;x++) {\n'
        '            ivec2 q=ivec2(floor(p.screen.xy))+ivec2(x,y);if(!inside(q)||!covered(p,vec2(q)+.5))continue;',
        'ivec2 center=ivec2(floor(p.screen.xy));\n'
        '        for(int y=max(0,center.y-bound);y<=min(parameters.counts.w-1,center.y+bound);y++) {\n'
        '          ivec2 span=lie_splat_row(p,center,y,bound);\n'
        '          for(int x=max(0,span.x);x<=min(parameters.counts.z-1,span.y);x++) {\n'
        '            ivec2 q=ivec2(x,y);if(footprint_distance(p,vec2(q)+.5)>1.)continue;')
    shader = shader.replace('        }return;', '          }\n        }return;')
    if stage == 2:
        shader = shader.replace('if(stage==2)atomicMin(depths.v[pixel],bits);',
            'if(stage==2) {\n'
            '                if(!covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds))continue;\n'
            '                atomicMin(depths.v[pixel],bits);\n            }')
    else:
        shader = shader.replace('if(stage==2)atomicMin(depths.v[pixel],bits);', 'if(stage==2)atomicMin(depths.v[pixel],bits);')
        shader = shader.replace('                if(depths.v[pixel]==bits)atomicMin(winners.v[pixel],i);\n'
            '                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;',
            '                if(abs(z-uintBitsToFloat(depths.v[pixel]))>parameters.options.w)continue;\n'
            '                if(!covered(p,vec2(q)+.5,s,inst,inverse_basis,bounds))continue;\n'
            '                if(depths.v[pixel]==bits)atomicMin(winners.v[pixel],i);')
    return shader
