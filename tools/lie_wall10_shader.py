"""Same reconstruction ABI plus common source visibility and source-ID cache."""
from pathlib import Path
from lie_wall09_shader import generate as baseline
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=baseline()
    header='''
layout(set=0,binding=25,std430) readonly buffer SourceBLAS {vec4 values[];} lie_visibility_blas;
layout(set=0,binding=26,std430) readonly buffer SourceLeaves {uint values[];} lie_visibility_refs;
layout(set=0,binding=27,std430) readonly buffer SourceScene {uint values[];} lie_visibility_scene;
layout(set=0,binding=28,std430) buffer SourceVisibility {uvec2 values[];} source_visibility;
vec4 lie_visibility_position_radius(uint sid) {return samples.v[sid].position_radius;}
vec3 lie_visibility_normal(uint sid) {return samples.v[sid].normal_gray.xyz;}
'''+(ROOT/'gpu_compute/shaders/lib/lie_source_visibility.glslinc').read_text()+'''
float lie_cached_source_visibility(uint projection,uint light) {
    uvec2 bits=source_visibility.values[projection];
    if(light<4u)return float((bits.x>>(light*8u))&255u)/255.;
    uint shift=(light-4u)*8u,mask=light==7u?127u:255u;
    return float((bits.y>>shift)&mask)/float(mask);
}
void lie_build_source_visibility(uint i) {
    if(i>=uint(parameters.counts.x))return;
    uvec2 bits=source_visibility.values[i];if((bits.y&0x80000000u)==0u)return;
    bits=uvec2(0xffffffffu);
    if(surface_options.flags.x!=0u && surface_options.flags.w!=0u) {
        Projection p=projected.v[i];
        for(uint l=0u;l<surface_lights.header.y;l++) {
            vec3 power=surface_lights.values[l*2u+1u].rgb;float visibility=1.;
            if(max(power.r,max(power.g,power.b))>0.)
                visibility=lie_source_world_visibility(p.world.xyz,normalize(p.normal.xyz),surface_lights.values[l*2u].xyz,
                    surface_options.metric.x,surface_options.metric.y,uint(p.gradient.z),uint(round(p.gradient.w)));
            uint mask=l==7u?127u:255u,shift=(l%4u)*8u;
            uint value=uint(round(clamp(visibility,0.,1.)*float(mask)));
            if(l<4u)bits.x=(bits.x&~(mask<<shift))|(value<<shift);
            else bits.y=(bits.y&~(mask<<shift))|(value<<shift);
        }
    }
    // Top bit is a persistent winner marker, surviving light-only changes.
    source_visibility.values[i]=bits;
}
'''
    s=replace(s,'void lie_resolve_surface(uint i) {',header+'\nvoid lie_resolve_surface(uint i) {')
    s=replace(s,'vec3 world,normal;vec3 coefficients[9];','uint source_projection=owner;\n    vec3 world,normal;vec3 coefficients[9];')
    s=replace(s,'world=surface.world.xyz;normal=surface.normal.xyz;','world=surface.world.xyz;normal=surface.normal.xyz;source_projection=uint(surface.normal.w)-1u;')
    s=replace(s,'''if(surface_options.flags.x!=0u && max(old_direct.r,max(old_direct.g,old_direct.b))>0.)
            visibility=lie_contact_visibility(world,normal,surface_lights.values[l*2u].xyz,
                surface_options.metric.x,surface_options.metric.y,int(surface_options.flags.z));''','''if(surface_options.flags.x!=0u && max(old_direct.r,max(old_direct.g,old_direct.b))>0.) {
            if(surface_options.flags.w!=0u)visibility=lie_cached_source_visibility(source_projection,l);
            else visibility=lie_contact_visibility(world,normal,surface_lights.values[l*2u].xyz,
                surface_options.metric.x,surface_options.metric.y,int(surface_options.flags.z));
        }''')
    s=replace(s,'if(stage==10) {lie_resolve_surface(i);return;}','if(stage==10) {lie_resolve_surface(i);return;}\n    if(stage==11) {lie_build_source_visibility(i);return;}')
    s=replace(s,'if(stage==1) {','if(stage==1) {\n        if(i<uint(parameters.counts.x))source_visibility.values[i]=uvec2(0);')
    s=replace(s,'if(depths.v[pixel]==bits)atomicMin(winners.v[pixel],i);','if(depths.v[pixel]==bits) {atomicMin(winners.v[pixel],i);atomicOr(source_visibility.values[i].y,0x80000000u);}')
    s=replace(s,'surface.normal=vec4(chosen_normal,0);','surface.normal=vec4(chosen_normal,float(chosen_owner+1u));')
    return s
if __name__=='__main__':(ROOT/'gpu_compute/shaders/lie_wall10_source.glsl').write_text(generate())
