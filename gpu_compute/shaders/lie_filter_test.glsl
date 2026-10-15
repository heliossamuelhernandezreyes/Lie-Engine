#[compute]
#version 450
layout(local_size_x=64) in;
struct Projection {vec4 world;vec4 normal;vec4 screen;vec4 gradient;vec4 geometry;vec4 ellipse;};
struct Accumulator {uvec4 color_weight;uvec4 normal_roughness;};
layout(set=0,binding=0,std430) readonly buffer Accumulated {Accumulator v[];} accumulated;
layout(set=0,binding=1,std430) readonly buffer Winners {uint v[];} winners;
layout(set=0,binding=2,std430) readonly buffer Projected {Projection v[];} projected;
layout(set=0,binding=3,std430) readonly buffer Parameters {ivec4 counts;vec4 lens;} parameters;
layout(set=0,binding=4,std430) buffer Results {uint v[];} results;
layout(push_constant,std430) uniform Phase {uvec4 data;} phase;
const uint EMPTY=0xffffffffu;
bool inside(ivec2 p){return p.x>=0 && p.y>=0 && p.x<parameters.counts.z && p.y<parameters.counts.w;}
uint projection_node(Projection p){return uint(p.world.w);}
uvec2 lie_group(uint node){return uvec2(node,1);}
float pixel_depth(Projection p,vec2 xy){return 1./(1./p.screen.z+dot(p.gradient.xy,xy-p.screen.xy));}
// A material packet uses the existing 16-byte image, without a new
// full-frame allocation. Geometry, winners and uncovered pixels are immutable.
struct LiePixelMaterial {vec3 albedo;vec3 mean_normal;float roughness;float mean_length;};
LiePixelMaterial lie_raw_material(uint i) {
    Accumulator a=accumulated.v[i];float w=max(float(a.color_weight.w),1.);
    vec3 n=vec3(a.normal_roughness.xyz)/w*2.-1.;
    return LiePixelMaterial(vec3(a.color_weight.xyz)/w,n,float(a.normal_roughness.w)/w,min(length(n),1.));
}
uvec4 lie_pack_material(LiePixelMaterial m) {
    return uvec4(packHalf2x16(m.albedo.rg),packHalf2x16(vec2(m.albedo.b,m.roughness)),packHalf2x16(m.mean_normal.xy),packHalf2x16(vec2(m.mean_normal.z,m.mean_length)));
}
LiePixelMaterial lie_unpack_material(uvec4 b) {
    vec2 a=unpackHalf2x16(b.x),c=unpackHalf2x16(b.y),n=unpackHalf2x16(b.z),z=unpackHalf2x16(b.w);
    return LiePixelMaterial(vec3(a,c.x),vec3(n,z.x),c.y,z.y);
}
LiePixelMaterial lie_filter_material(uint i) {
    LiePixelMaterial center=lie_raw_material(i);uint owner=winners.v[i];
    if(owner==EMPTY)return center;
    Projection p=projected.v[owner];uvec2 group=lie_group(projection_node(p));
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    float sigma=clamp(.35+.12*p.screen.w,.45,1.);
    float world_pixel=2.*p.screen.z*parameters.lens.x/float(parameters.counts.z);
    float tolerance=clamp(world_pixel*1.25,.0004,.002);
    vec3 color=vec3(0),normal=vec3(0);float rough=0.,sum=0.;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {
        ivec2 q=xy+ivec2(x,y);if(!inside(q))continue;
        uint j=uint(q.y*parameters.counts.z+q.x),other=winners.v[j];if(other==EMPTY)continue;
        Projection neighbor=projected.v[other];
        if(neighbor.gradient.z!=p.gradient.z || any(notEqual(group,lie_group(projection_node(neighbor)))))continue;
        if(dot(normalize(p.normal.xyz),normalize(neighbor.normal.xyz))<.95)continue;
        // Compare both planes at the same pixel center; never blur a depth edge.
        float observed=pixel_depth(neighbor,vec2(q)+.5);
        float expected=pixel_depth(p,vec2(q)+.5);
        if(abs(expected-observed)>tolerance)continue;
        LiePixelMaterial m=lie_raw_material(j);vec3 delta=m.albedo-center.albedo;
        float weight=exp(-float(x*x+y*y)/(2.*sigma*sigma)-dot(delta,delta)/.0128);
        color+=m.albedo*weight;normal+=m.mean_normal*weight;rough+=m.roughness*weight;sum+=weight;
    }
    if(sum<=0.)return center;
    normal/=sum;return LiePixelMaterial(color/sum,normal,rough/sum,min(length(normal),1.));
}

void main(){
 uint i=gl_GlobalInvocationID.x;if(i>=uint(parameters.counts.z*parameters.counts.w))return;
 if(winners.v[i]==EMPTY){for(uint k=0u;k<8u;k++)results.v[i*8u+k]=0u;return;}
 if(phase.data.x==0u){uvec4 b=lie_pack_material(lie_filter_material(i));for(uint k=0u;k<4u;k++)results.v[i*8u+k]=b[k];return;}
 LiePixelMaterial m=lie_unpack_material(uvec4(results.v[i*8u],results.v[i*8u+1u],results.v[i*8u+2u],results.v[i*8u+3u]));
 for(uint k=0u;k<3u;k++){results.v[i*8u+k]=floatBitsToUint(m.albedo[k]);results.v[i*8u+4u+k]=floatBitsToUint(m.mean_normal[k]);}
 results.v[i*8u+3u]=floatBitsToUint(m.roughness);results.v[i*8u+7u]=floatBitsToUint(m.mean_length);
}
