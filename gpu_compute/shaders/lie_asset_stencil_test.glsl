#[compute]
#version 450
layout(local_size_x=64) in;
struct Node {vec4 position_area;vec4 normal_pad;uvec4 group;};
layout(set=0,binding=0,std430) readonly buffer Queries {vec4 entries[];} queries;
layout(set=0,binding=1,std430) readonly buffer Nodes {Node entries[];} nodes;
layout(set=0,binding=2,std430) buffer Result {float entries[];} result;
layout(push_constant,std430) uniform Parameters {ivec4 counts;} parameters;
uvec2 lie_group(uint node) {return nodes.entries[node].group.xy;}
vec3 lie_position(uint node) {return nodes.entries[node].position_area.xyz;}
vec3 lie_normal(uint node) {return nodes.entries[node].normal_pad.xyz;}
float lie_area(uint node) {return nodes.entries[node].position_area.w;}
// Shared LIE11 irradiance reconstruction, with source-authored node groups.
// Host provides lie_group(node), lie_position(node), lie_normal(node).
// Convex weights do not overshoot compatible node irradiances. This does not
// prove exact area-integrated flux or replace the passive transport solver.
float lie_stencil_weight(vec3 world,uint reference,uint candidate) {
    vec3 normal=normalize(lie_normal(reference));
    float agreement=dot(normal,normalize(lie_normal(candidate)));
    if(agreement<.9)return 0.;
    vec3 delta=world-lie_position(candidate);delta-=normal*dot(delta,normal);
    float alignment=max((agreement-.9)/.1,0.);
    return alignment*alignment/(dot(delta,delta)+max(lie_area(reference)*1e-4,1e-12));
}
float lie_stencil_sum(vec3 world,uint node) {
    uvec2 group=lie_group(node);float total=0.;
    for(uint k=0u;k<group.y;k++)total+=lie_stencil_weight(world,node,group.x+k);
    return total;
}

void main() {
 uint i=gl_GlobalInvocationID.x;if(i>=uint(parameters.counts.x))return;
 vec3 point=queries.entries[i].xyz;uint node=uint(queries.entries[i].w);uvec2 group=lie_group(node);
 float sum=lie_stencil_sum(point,node);
 for(uint k=0u;k<uint(parameters.counts.y);k++)result.entries[i*uint(parameters.counts.y)+k]=k>=group.x && k<group.x+group.y?lie_stencil_weight(point,node,k)/sum:0.;
}
