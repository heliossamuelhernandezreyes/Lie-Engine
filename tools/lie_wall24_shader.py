"""Hardware footprint rasterization of the accepted opaque LIE samples.

Projection, disk coverage, depth, IDs and integer material terms are inherited
from 1.4. Graphics MIN/ADD attachments replace the footprint's scattered depth
and eight material atomics. Owner/source flags retain their original atomics.
This experimental path requires float32 blending and exact integer sums below
2**24; real-bank acceptance must establish its useful domain and performance.
"""
import json
import re
from pathlib import Path
from lie_wall17_shader import generate, functions, mask

ROOT = Path(__file__).resolve().parents[1]

def compile_source(main, extra="", kind="compute"):
    original, _ = generate(3)
    defs = functions(original)
    by_name = {f[0]: f[3] for f in defs if f[0] != "main"}
    needed, pending = set(), [main]
    while pending:
        calls = set(re.findall(r"\b(\w+)\s*\(", mask(pending.pop())))
        for name in sorted((calls & by_name.keys()) - needed):
            needed.add(name)
            pending.append(by_name[name])
    # Retain declarations/constants and the source order of needed helpers.
    prefix = original[:defs[0][1]]
    # Declarations can occur between helper functions in the accepted source.
    for _, start, end, _ in reversed(defs):
        original = original[:start] + original[end:]
    source = original + "\n" + extra + "\n"
    source += "\n".join(f[3] for f in defs if f[0] in needed) + "\n" + main
    declarations = list(re.finditer(
        r"layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*"
        r"(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)"
        r"|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;",
        source, re.S))
    used = source
    for m in reversed(declarations): used = used[:m.start()] + used[m.end():]
    bindings = []
    for m in reversed(declarations):
        if not re.search(r"\b" + (m[2] or m[3]) + r"\b", mask(used)):
            source = source[:m.start()] + source[m.end():]
        else: bindings.append(int(m[1]))
    source = re.sub(r"layout\(local_size_x=64\) in;", "", source)
    source = source.replace("#[compute]", "#[" + kind + "]")
    if kind == "compute": source = source.replace("#version 450", "#version 450\nlayout(local_size_x=64) in;", 1)
    return source, sorted(bindings)

VERTEX = r'''
layout(location=0) flat out uint projection_id;
void main() {
    uint invocation=gl_InstanceIndex, i=invocation;
    if(phase.value.w!=0) {
        uint group=invocation/64u;
        if(phase.value.w<0 && group>=query_arena.words[0]) {gl_Position=vec4(2,2,2,1);projection_id=EMPTY;return;}
        uint block_id=phase.value.w<0?query_arena.words[4u+group]:uint(phase.value.w)-1u+group;
        uvec2 block=source_blocks.values[block_id];
        uint local=block.y+invocation%64u;
        if(local>=jobs.v[block.x].y) {gl_Position=vec4(2,2,2,1);projection_id=EMPTY;return;}
        i=jobs.v[block.x].w+local;
    } else if(i>=uint(parameters.counts.x)) {
        gl_Position=vec4(2,2,2,1);projection_id=EMPTY;return;
    }
    Projection p=projected.v[i];projection_id=i;
    if(p.screen.z<=0) {gl_Position=vec4(2,2,2,1);return;}
    const vec2 corners[6]=vec2[6](vec2(0,0),vec2(1,0),vec2(0,1),vec2(0,1),vec2(1,0),vec2(1,1));
    int bound=int(ceil(p.screen.w));vec2 low=floor(p.screen.xy)-vec2(bound);
    vec2 xy=low+corners[gl_VertexIndex]*float(bound*2+1);
    gl_Position=vec4(xy/vec2(parameters.counts.zw)*2.-1.,0.,1.);
}
'''
FRAGMENT_COMMON = r'''
    uint i=projection_id;if(i==EMPTY)discard;
    Projection p=projected.v[i];ivec2 q=ivec2(gl_FragCoord.xy);vec2 xy=vec2(q)+.5;
    if(!inside(q)||!covered(p,xy))discard;
    float z=pixel_depth(p,xy);if(z<=parameters.lens.z||isnan(z)||isinf(z))discard;
'''
DEPTH = "layout(location=0) flat in uint projection_id;\nlayout(location=0) out float out_depth;\nvoid main(){\n" + FRAGMENT_COMMON + "out_depth=z;\n}\n"
MATERIAL = r'''
layout(location=0) flat in uint projection_id;
layout(location=0) out vec4 out_color_weight;
layout(location=1) out vec4 out_normal_roughness;
void main(){
''' + FRAGMENT_COMMON + r'''
    uint pixel=uint(q.y*parameters.counts.z+q.x);
    float nearest=texelFetch(graphics_depth,q,0).r;
    if(floatBitsToUint(nearest)==floatBitsToUint(z)) {
        atomicMin(winners.v[pixel],i);atomicOr(source_visibility.values[i].y,0x80000000u);
    }
    if(abs(z-nearest)>parameters.options.w)discard;
    uint j=job_index(i);uvec4 job=jobs.v[j];
    uint sid=sample_refs.values[job.x+i-job.w];
    Instance source_inst=instances.v[job.z];Sample s=fetch_sample(sid,source_inst);Instance inst=render_instance(source_inst);
    vec3 sample_color=material_color(s,inst);float sample_rough=clamp(s.attributes.z+inst.tint.w,.2,.95);
    if(int(s.attributes.x)==3 || int(s.attributes.x)==6) {
        uint id=uint(max(inst.meta.x,0));if(inst.meta.y>.5)id+=uint(int(s.attributes.y)%2+6*(int(s.attributes.y)/2));
        sample_rough=clamp(sample_rough+(variation(id)-.5)*parameters.wall.w*.3,.2,.95);
    }
    uint w=max(uint(round(256*exp(-2*footprint_distance(p,xy)))),1u);
    uvec3 c=uvec3(round(sample_color*float(w))),n=uvec3(round((p.normal.xyz*.5+.5)*float(w)));
    out_color_weight=vec4(c,w);out_normal_roughness=vec4(n,uint(round(sample_rough*float(w))));
}
'''
RESOLVE = r'''
void main(){
    uint i=gl_GlobalInvocationID.x;if(i>=uint(parameters.counts.z*parameters.counts.w))return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    float z=texelFetch(graphics_depth,xy,0).r;
    depths.v[i]=floatBitsToUint(z);
    vec4 a=texelFetch(graphics_color,xy,0),b=texelFetch(graphics_normal,xy,0);
    if(a.w>=16777216.)atomicOr(draw_arguments.diagnostics.x,1u);
    accumulated.v[i].color_weight=uvec4(round(a));
    accumulated.v[i].normal_roughness=uvec4(round(b));
}
'''
ARGS = r'''
void main(){
    if(gl_GlobalInvocationID.x!=0u)return;
    draw_arguments.values=uvec4(6u,phase.value.w<0?query_arena.words[0]*64u:uint(phase.value.x),0u,0u);
    draw_arguments.diagnostics=uvec4(0);
}
'''
EXTRA = "layout(set=0,binding=45) uniform sampler2D graphics_depth;\nlayout(set=0,binding=46) uniform sampler2D graphics_color;\nlayout(set=0,binding=47) uniform sampler2D graphics_normal;\n"
DRAW_ARGUMENTS = "layout(set=0,binding=48,std430) buffer DrawArguments {uvec4 values;uvec4 diagnostics;} draw_arguments;"

def outputs():
    result, manifest = {}, {}
    # Project the identical source work; omit only the software footprint loop.
    source, _ = generate(2)
    main = next(f[3] for f in functions(source) if f[0] == "main")
    main = main[:main.index("        if(p.screen.z<=0)return;")] + "\n}\n"
    for name, body, extra in [("project",main,""),("args",ARGS,DRAW_ARGUMENTS),("resolve",RESOLVE,EXTRA+DRAW_ARGUMENTS)]:
        shader, bindings = compile_source(body,extra)
        result[f"gpu_compute/shaders/lie_wall24_{name}.glsl"] = shader
        manifest[name] = bindings
    vertex, vb = compile_source(VERTEX,kind="vertex")
    for name, fragment, extra in [("depth",DEPTH,""),("material",MATERIAL,EXTRA)]:
        frag, fb = compile_source(fragment,extra,kind="fragment")
        result[f"gpu_compute/shaders/lie_wall24_{name}.glsl"] = vertex + "\n" + frag
        manifest[name] = sorted(set(vb+fb))
    gd = 'extends RefCounted\n## Generated hardware footprint shader manifest.\nconst SHADERS={\n'
    for name in manifest: gd += f'    "{name}":preload("res://shaders/lie_wall24_{name}.glsl"),\n'
    gd += '}\nconst BINDINGS='+json.dumps(manifest,separators=(',',':'))+'\n'
    result["gpu_compute/lie_graphics_splat_kernels.gd"] = gd
    return result

if __name__ == "__main__":
    for name, source in outputs().items(): (ROOT/name).write_text(source)
