"""Connect the reusable stencil to the existing source-only reconstruction."""
from pathlib import Path
from lie_wall05_shader import generate as baseline,replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=baseline()
    header='''layout(set=0,binding=21,std430) readonly buffer LightGroups { uvec4 header; uvec4 entries[]; } light_groups;
uvec2 lie_group(uint node) {return light_groups.header.x==0u?uvec2(node,1):light_groups.entries[node].xy;}
vec3 lie_position(uint node) {return injected_material_codes.values[node*3u].xyz;}
vec3 lie_normal(uint node) {return injected_material_codes.values[node*3u+1u].xyz;}
float lie_area(uint node) {return injected_material_codes.values[node*3u].w;}
'''
    helper=(ROOT/'gpu_compute/shaders/lib/lie_irradiance_stencil.glslinc').read_text()
    s=replace(s,'const int SHADOW_SIZE=512;','const int SHADOW_SIZE=512;\n'+header+helper+'''
vec3 lie_irradiance_code(Projection point) {
    uint node=projection_node(point);uvec2 group=lie_group(node);
    vec3 total=vec3(0);float sum=group.y==1u?1.:lie_stencil_sum(point.world.xyz,node);
    for(uint k=0u;k<group.y;k++) {
        uint candidate=group.x+k;
        float w=group.y==1u?1.:lie_stencil_weight(point.world.xyz,node,candidate)/max(sum,1e-30);
        vec3 E=max(imageLoad(injected_node_irradiance,ivec2(int(candidate),0)).rgb,vec3(0));
        float absorption=clamp(injected_material_codes.values[candidate*3u+2u].w,0.,1.);
        total+=w*E*(1.-absorption)/PI;
    }
    return total;
}
''')
    s=replace(s,'uint node_base=chosen_group<96u?chosen_group*9u:864u+chosen_group-96u;', '''uint reference_node=chosen_group<96u?chosen_group*9u:864u+chosen_group-96u;
        uvec2 recovery_group=light_groups.entries[reference_node].xy;
        uint node_base=recovery_group.x;''')
    s=replace(s,'coeff[node-node_base]+=albedo*(weight/PI);','''uvec2 stencil=lie_group(node);
            float stencil_sum=stencil.y==1u?1.:lie_stencil_sum(pr.world.xyz,node);
            for(uint k=0u;k<stencil.y;k++) {
                uint candidate=stencil.x+k;
                float w=stencil.y==1u?1.:lie_stencil_weight(pr.world.xyz,node,candidate)/max(stencil_sum,1e-30);
                coeff[candidate-node_base]+=albedo*(weight*w/PI);
            }''')
    s=replace(s,'chosen_group<96u?9u:1u,0,0','recovery_group.y,0,0')
    s=replace(s,'vec3 diffuse_code=E*(1.-absorption)/PI;','vec3 diffuse_code=lie_irradiance_code(point);')
    return s
if __name__=='__main__':(ROOT/'gpu_compute/shaders/lie_wall07_continuous.glsl').write_text(generate())
