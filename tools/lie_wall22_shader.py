"""Screen-owned raster experiment; original projection and integer material math.

8x8 tiles use exact, dynamically counted CSR lists, never a fixed per-tile cap.
The original maximum footprint radius is eight pixels, hence at most nine
tile references per source. Depth ties and integer accumulation are unchanged.
"""
import json,re
from pathlib import Path
from lie_wall17_shader import generate,functions,mask
ROOT=Path(__file__).resolve().parents[1]
DECL='''
// Per-tile count, fill cursor, block-local exclusive offset, reserved.
layout(set=0,binding=41,std430) buffer TileTable { uvec4 values[]; } tile_table;
layout(set=0,binding=42,std430) buffer TileReferences { uint values[]; } tile_refs;
// One exclusive prefix per 64-tile block, then total reference count.
layout(set=0,binding=43,std430) buffer TileGroups { uint values[]; } tile_groups;
layout(set=0,binding=44,std430) buffer TileMaterials { vec4 values[]; } tile_materials;
const uint LIE_TILE_SIZE=8u;
uvec2 lie_tile_dimensions(){return (uvec2(parameters.counts.zw)+7u)/8u;}
uint lie_tile_count(){uvec2 d=lie_tile_dimensions();return d.x*d.y;}
uint lie_tile_start(uint tile){return tile_table.values[tile].z+tile_groups.values[tile/64u];}
bool lie_tile_range(Projection p,out ivec4 range){
    if(p.screen.z<=0.)return false;
    int bound=int(ceil(p.screen.w));ivec2 center=ivec2(floor(p.screen.xy));
    ivec2 lo=max(center-ivec2(bound),ivec2(0));
    ivec2 hi=min(center+ivec2(bound),parameters.counts.zw-ivec2(1));
    if(any(greaterThan(lo,hi)))return false;
    range=ivec4(lo/8,hi/8);return true;
}
bool lie_tile_hit(Projection p,ivec2 q,out uint bits){
    int bound=int(ceil(p.screen.w));ivec2 center=ivec2(floor(p.screen.xy));
    if(any(lessThan(q,center-ivec2(bound))) || any(greaterThan(q,center+ivec2(bound))))return false;
    if(appearance_control.words[1]!=0u){ivec2 row=lie_splat_row(p,center,q.y,bound);if(q.x<row.x || q.x>row.y)return false;}
    if(!covered(p,vec2(q)+.5))return false;
    float z=pixel_depth(p,vec2(q)+.5);if(z<=parameters.lens.z || isnan(z) || isinf(z))return false;
    bits=floatBitsToUint(z);return true;
}
'''

def prune(source):
    """Keep helper closure and descriptors actually used by this entry point."""
    fs=functions(source);by_name={f[0]:f[3] for f in fs};needed={'main'};pending=['main']
    while pending:
        for name in set(re.findall(r'\b(\w+)\s*\(',mask(by_name[pending.pop()]))) & by_name.keys()-needed:
            needed.add(name);pending.append(name)
    for name,start,end,_ in reversed(fs):
        if name not in needed:source=source[:start]+source[end:]
    declarations=list(re.finditer(r'layout\([^;]*?binding\s*=\s*(\d+)[^;]*?\)\s*(?:readonly\s+|writeonly\s+)?(?:buffer\s+\w+\s*\{[^}]*\}\s*(\w+)|uniform\s+(?:readonly\s+|writeonly\s+)?\w+\s+(\w+))\s*;',source,re.S))
    used=source
    for m in reversed(declarations):used=used[:m.start()]+used[m.end():]
    bindings=[]
    for m in reversed(declarations):
        if not re.search(r'\b'+(m[2] or m[3])+r'\b',mask(used)):source=source[:m.start()]+source[m.end():]
        else:bindings.append(int(m[1]))
    return source,sorted(bindings)

def outputs():
    original=generate(3)[0]
    assert 'clamp(sqrt(max(xx,yy)),.5,8)' in original
    main=next(f[3] for f in functions(original) if f[0]=='main')
    # Keep the accepted source schedule, transforms, normal and projection.
    prefix=main[:main.index('        int bound=int(ceil(p.screen.w));')]
    prefix=prefix.replace('const int stage=3;','const int stage=2;')
    material=main[main.index('        vec3 sample_color=stage==3?'):main.index('        uint candidates=0u;')]
    material=material.replace('stage==3?', 'true?').replace('stage==3 && ', '')
    project=prefix+material+'''
        tile_materials.values[i]=vec4(sample_color,sample_rough);
        ivec4 range;if(!lie_tile_range(p,range))return;
        uint columns=lie_tile_dimensions().x;
        for(int y=range.y;y<=range.w;y++)for(int x=range.x;x<=range.z;x++)
            atomicAdd(tile_table.values[uint(y)*columns+uint(x)].x,1u);
}
'''
    # Reuse the identical source-index selection for filling after prefix sums.
    selection=main[:main.index('        uvec4 job=jobs.v[j];')]
    fill=selection+'''
        Projection p=projected.v[i];ivec4 range;if(!lie_tile_range(p,range))return;
        uint columns=lie_tile_dimensions().x;
        for(int y=range.y;y<=range.w;y++)for(int x=range.x;x<=range.z;x++){
            uint tile=uint(y)*columns+uint(x);
            uint at=atomicAdd(tile_table.values[tile].y,1u);
            tile_refs.values[lie_tile_start(tile)+at]=i;
        }
}
'''
    reset='''void main(){
    uint i=gl_GlobalInvocationID.x;if(i<lie_tile_count())tile_table.values[i]=uvec4(0);
}
'''
    scan='''shared uint lie_scan[64];
void main(){
    uint i=gl_GlobalInvocationID.x,lane=gl_LocalInvocationID.x;
    uint value=i<lie_tile_count()?tile_table.values[i].x:0u;
    lie_scan[lane]=value;barrier();
    for(uint offset=1u;offset<64u;offset*=2u){
        uint addend=lane>=offset?lie_scan[lane-offset]:0u;
        barrier();lie_scan[lane]+=addend;barrier();
    }
    if(i<lie_tile_count())tile_table.values[i].z=lie_scan[lane]-value;
    if(lane==63u)tile_groups.values[gl_WorkGroupID.x]=lie_scan[lane];
}
'''
    groups='''void main(){
    if(gl_GlobalInvocationID.x!=0u)return;
    uint count=(lie_tile_count()+63u)/64u,total=0u;
    for(uint i=0u;i<count;i++){uint value=tile_groups.values[i];tile_groups.values[i]=total;total+=value;}
    tile_groups.values[count]=total;
}
'''
    resolve='''void main(){
    uint tile=gl_WorkGroupID.x;uvec2 dims=lie_tile_dimensions();
    ivec2 q=ivec2(tile%dims.x,tile/dims.x)*8+ivec2(gl_LocalInvocationID.x%8u,gl_LocalInvocationID.x/8u);
    if(!inside(q))return;
    uint pixel=uint(q.y*parameters.counts.z+q.x),count=tile_table.values[tile].x,start=lie_tile_start(tile);
    uint nearest=0x7f7fffffu,owner=EMPTY;
    for(uint k=0u;k<count;k++){
        uint id=tile_refs.values[start+k],bits;Projection p=projected.v[id];
        if(lie_tile_hit(p,q,bits))nearest=min(nearest,bits);
    }
    Accumulator a=Accumulator(uvec4(0),uvec4(0));
    if(nearest!=0x7f7fffffu)for(uint k=0u;k<count;k++){
        uint id=tile_refs.values[start+k],bits;Projection p=projected.v[id];
        if(!lie_tile_hit(p,q,bits))continue;
        if(bits==nearest){owner=min(owner,id);atomicOr(source_visibility.values[id].y,0x80000000u);}
        if(abs(uintBitsToFloat(bits)-uintBitsToFloat(nearest))>parameters.options.w)continue;
        vec4 material=tile_materials.values[id];
        uint w=max(uint(round(256*exp(-2*footprint_distance(p,vec2(q)+.5)))),1u);
        uvec3 c=uvec3(round(material.rgb*float(w))),n=uvec3(round((p.normal.xyz*.5+.5)*float(w)));
        a.color_weight+=uvec4(c,w);
        a.normal_roughness+=uvec4(n,uint(round(material.w*float(w))));
    }
    depths.v[pixel]=nearest;winners.v[pixel]=owner;accumulated.v[pixel]=a;
}
'''
    base=original[:original.index('void main() {')]
    files={};bindings={}
    for key,body in [('reset',reset),('project',project),('scan',scan),('groups',groups),('fill',fill),('resolve',resolve)]:
        source,binding=prune(base+DECL+body)
        source=source.replace('// GENERATED dedicated stage 3; tools/lie_wall17_shader.py','// GENERATED screen-owned '+key+'; tools/lie_wall22_shader.py')
        files[f'gpu_compute/shaders/lie_wall22_{key}.glsl']=source;bindings[key]=binding
    gd='extends RefCounted\n## Generated screen-tile shaders; original source identity and pixel math.\nconst SHADERS={\n'
    for key in bindings:gd+=f'    "{key}":preload("res://shaders/lie_wall22_{key}.glsl"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':'))+'\n'
    files['gpu_compute/lie_screen_tile_kernels.gd']=gd
    return files

if __name__=='__main__':
    for name,source in outputs().items():(ROOT/name).write_text(source)
