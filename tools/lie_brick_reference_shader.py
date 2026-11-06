"""Keep the accepted LIE-28 camera reconstruction; inject the shared light field.

This consumer deliberately evaluates Lambert direct radiance for the matte
benchmark. It is not a replacement for the production GGX surface consumer.
"""
import argparse
import json
import re
from pathlib import Path
from lie_wall05_shader import replace
from lie_wall17_shader import functions,mask,end_brace
ROOT = Path(__file__).resolve().parents[1]


def generate(full_shadow_support=True,indirect_prepass=True):
    s = (ROOT/'gpu_compute/shaders/lie28_building.glsl').read_text()
    header = '''
layout(set=0,binding=14,std430) readonly buffer BenchData {uvec4 header;vec4 v[];} bench;
layout(rgba32f,set=0,binding=15) uniform readonly image2D field_irradiance;
layout(set=0,binding=16,std430) readonly buffer SurfaceLights {uvec4 header;vec4 values[];} surface_lights;
layout(set=0,binding=18,std430) readonly buffer Emission {vec4 v[];} emission;
vec3 lie_position(uint node){return bench.v[24u+node*3u].xyz;}
float lie_area(uint node){return bench.v[24u+node*3u].w;}
vec3 lie_normal(uint node){return bench.v[24u+node*3u+1u].xyz;}
uvec2 lie_group(uint node){return uvec2(bench.v[24u+node*3u+2u].xy);}
vec3 bench_indirect(vec3 p,uint node) {
    uvec2 group=lie_group(node);float sum=lie_stencil_sum(p,node);vec3 result=vec3(0);
    for(uint k=0u;k<group.y;k++) {
        uint j=group.x+k;float w=lie_stencil_weight(p,node,j)/max(sum,1e-30);
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++)direct+=surface_lights.values[16u+l*bench.header.x+j].rgb;
        result+=w*max(imageLoad(field_irradiance,ivec2(int(j),0)).rgb-direct,vec3(0));
    }
    return result;
}
'''
    # Helper function declarations precede the shared stencil and its caller.
    prototypes = header[:header.index('vec3 bench_indirect')]
    helper = (ROOT/'gpu_compute/shaders/lib/lie_irradiance_stencil.glslinc').read_text()
    direct = (ROOT/'gpu_compute/shaders/lib/lie_surface_direct.glslinc').read_text()
    emission = (ROOT/'gpu_compute/shaders/lib/lie_area_emission.glslinc').read_text()
    s = replace(s, 'const int SHADOW_SIZE=512;', 'const int SHADOW_SIZE=512;\n'+prototypes+helper+header[header.index('vec3 bench_indirect'):]+direct+emission)
    # Each physical channel owns a shadow layer. Same captured disk raster.
    begin = s.index('            vec3 ld=world-parameters.light.xyz;')
    end = s.index('            if(depth>parameters.lens.z', begin)
    original = s[begin:end]
    layered = original.replace('parameters.light.xyz', 'surface_lights.values[light*2u].xyz')
    for name, row in [('right', 0), ('up', 1), ('forward', 2)]:
        layered = layered.replace('parameters.shadow_'+name+'.xyz', f'bench.v[light*3u+{row}u].xyz')
    layered = layered.replace('shadow.v[q.y*SHADOW_SIZE+q.x]', 'shadow.v[light*uint(SHADOW_SIZE*SHADOW_SIZE)+uint(q.y*SHADOW_SIZE+q.x)]')
    # The inherited fixed 3x3 splat leaves a grid of unoccluded holes when a
    # source footprint projects to more than one light-map texel. Rasterize the
    # full projected support, and clip to the SAME authored face as the camera.
    if full_shadow_support:
        layered = replace(layered, 'for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {', '''float offset_ratio=max(abs(dot(ld,bench.v[light*3u].xyz)),abs(dot(ld,bench.v[light*3u+1u].xyz)))/lz;
                int shadow_bound=min(SHADOW_SIZE,int(ceil(radius*(1.+offset_ratio)*float(SHADOW_SIZE)/(2.*1.25*max(lz-radius,1e-6)))+1.));
                for(int y=-shadow_bound;y<=shadow_bound;y++)for(int x=-shadow_bound;x<=shadow_bound;x++) {''')
        layered = replace(layered, 'if(z>.00001 && length(', '''vec3 local_hit=inverse(basis)*(surface_lights.values[light*2u].xyz+ray*z-inst.origin.xyz);
                    vec3 axis=abs(s.normal_gray.xyz);vec2 support_point=axis.x>=axis.y && axis.x>=axis.z?local_hit.zy:axis.y>=axis.z?local_hit.xz:local_hit.xy;
                    bool face_support=all(greaterThanEqual(support_point,s.support.xy-vec2(.000002))) && all(lessThanEqual(support_point,s.support.zw+vec2(.000002)));
                    if(face_support && z>.00001 && length(''')
    s = s[:begin]+'            for(uint light=0u;light<surface_lights.header.y;light++) {\n'+layered+'            }\n'+s[end:]
    s = replace(s, 'if(i<uint(SHADOW_SIZE*SHADOW_SIZE))shadow.v[i]=0x7f7fffffu;', 'if(i<uint(SHADOW_SIZE*SHADOW_SIZE))for(uint l=0u;l<8u;l++)shadow.v[l*uint(SHADOW_SIZE*SHADOW_SIZE)+i]=0x7f7fffffu;')
    begin = s.index('float visibility('); end = s.index('vec3 to_srgb', begin)
    visibility = s[begin:end].replace('float visibility(vec3 p,', 'float bench_visibility(uint light,vec3 p,')
    visibility = visibility.replace('parameters.light.xyz', 'surface_lights.values[light*2u].xyz')
    for name, row in [('right', 0), ('up', 1), ('forward', 2)]:
        visibility = visibility.replace('parameters.shadow_'+name+'.xyz', f'bench.v[light*3u+{row}u].xyz')
    visibility = visibility.replace('shadow.v[q.y*SHADOW_SIZE+q.x]', 'shadow.v[light*uint(SHADOW_SIZE*SHADOW_SIZE)+uint(q.y*SHADOW_SIZE+q.x)]')
    s = s[:begin]+visibility+s[end:]
    begin = s.index('        vec3 delta=parameters.light.xyz-p;'); end = s.index('return;\n    }', begin)
    s = s[:begin]+'''        Sample source=samples.v[uint(point.gradient.w)];
        uint node=uint(source.attributes.y)+uint(instances.v[uint(point.gradient.z)].meta.x);
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++) {
            vec3 E=lie_surface_unoccluded(l,p,n)*lie_emitter_gain(emission.v[l],p-surface_lights.values[l*2u].xyz);
            direct+=E*bench_visibility(l,p+point.geometry.xyz*parameters.options.z*.45,point.geometry.xyz);
        }
        imageStore(diffuse_image,xy,vec4(base*direct/PI,1));
        imageStore(specular_image,xy,vec4(base*bench_indirect(p,node)/PI,1));
        '''+s[end:]
    s = replace(s, 'imageStore(output_image,xy,vec4(max(base*imageLoad(diffuse_image,xy).rgb+imageLoad(specular_image,xy).rgb,vec3(0)),1));', '''vec3 direct=imageLoad(diffuse_image,xy).rgb,indirect=imageLoad(specular_image,xy).rgb;
        int mode=int(parameters.settings.w);
        imageStore(output_image,xy,vec4(max(mode==1?direct:mode==2?indirect:direct+indirect,vec3(0)),1));''')
    s = replace(s, 'imageStore(final_image,xy,vec4(to_srgb(linear/(vec3(1)+linear)),coverage/float(scale*scale)));', 'imageStore(final_image,xy,vec4(linear,coverage/float(scale*scale)));')
    if full_shadow_support and indirect_prepass:
        s=replace(s,'vec3 bench_indirect(vec3 p,uint node) {','layout(set=0,binding=19,std430) buffer IndirectNodes {vec4 v[];} indirect_nodes;\nvec3 bench_indirect(vec3 p,uint node) {')
        s=replace(s,'''        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++)direct+=surface_lights.values[16u+l*bench.header.x+j].rgb;
        result+=w*max(imageLoad(field_irradiance,ivec2(int(j),0)).rgb-direct,vec3(0));''','''        result+=w*indirect_nodes.v[j].rgb;''')
        s=replace(s,'    if(stage==7) {','''    if(stage==8) {
        if(i>=bench.header.x)return;
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++)direct+=surface_lights.values[16u+l*bench.header.x+i].rgb;
        indirect_nodes.v[i]=vec4(max(imageLoad(field_irradiance,ivec2(int(i),0)).rgb-direct,vec3(0)),1);
        return;
    }
    if(stage==7) {''')
    return s


def dedicated(stage):
    """Same equations in isolated entries, using the accepted closure compiler."""
    source=generate();all_functions=functions(source);main=next(f[3] for f in all_functions if f[0]=='main')
    common=main[:main.index('    if(stage==1)')].replace('int stage=phase.value.x;',f'const int stage={stage};')
    if stage in (4,6):
        branch=main[main.index('    if(i>=pixels) return;'):main.rfind('}')]
    else:
        key=2 if stage==3 else stage
        match=re.search(r'    if\(stage=='+str(key)+r'(?:\)| \|\| stage==\d+\))\s*\{',mask(main))
        if match is None:raise ValueError('Missing camera stage')
        end=end_brace(mask(main),match.end()-1);branch=main[match.end():end-1]
    entry=common+branch+'\n}\n'
    by_name={f[0]:f for f in all_functions if f[0]!='main'};needed=set();pending=[entry]
    while pending:
        calls=set(re.findall(r'\b(\w+)\s*\(',mask(pending.pop())))
        for name in sorted(calls&by_name.keys()-needed):needed.add(name);pending.append(by_name[name][3])
    source=source[:all_functions[-1][1]]
    for name,start,end,_ in reversed(all_functions[:-1]):
        if name not in needed:source=source[:start]+source[end:]
    source+='\n'+entry
    declarations=list(re.finditer(r'layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;',source,re.S))
    used=source
    for m in reversed(declarations):used=used[:m.start()]+used[m.end():]
    bindings=[]
    for m in reversed(declarations):
        if re.search(r'\b'+(m[2] or m[3])+r'\b',mask(used)):bindings.append(int(m[1]))
        else:source=source[:m.start()]+source[m.end():]
    return '\n'.join(line.rstrip() for line in source.splitlines())+'\n',sorted(bindings)


def outputs():
    result={'gpu_compute/shaders/lie_brick_reference.glsl':generate()};bindings={}
    gd='extends RefCounted\n## Generated independent entries; identical captured equations.\nconst SHADERS={\n'
    for stage in (1,2,3,4,6,7,8):
        shader,bindings[stage]=dedicated(stage)
        result[f'gpu_compute/shaders/lie_brick_reference_stage_{stage}.glsl']=shader
        gd+=f'    {stage}:preload("res://shaders/lie_brick_reference_stage_{stage}.glsl"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':')).replace('"','')+'\n'
    result['gpu_compute/lie_brick_reference_kernels.gd']=gd
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);parser.add_argument('--legacy-shadow-footprint',action='store_true');args=parser.parse_args()
    if args.legacy_shadow_footprint and args.output is None:parser.error('Legacy replay requires an explicit --output; preserve the accepted generated shader')
    if args.output:args.output.write_text(generate(not args.legacy_shadow_footprint))
    else:
        for name,text in outputs().items():(ROOT/name).write_text(text)
