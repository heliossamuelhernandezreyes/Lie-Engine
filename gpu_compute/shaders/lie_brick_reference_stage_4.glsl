#[compute]
#version 450
// LIE28: source RGB albedo and roughness captured without lighting.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
struct Projection { vec4 world; vec4 normal; vec4 screen; vec4 gradient; vec4 geometry; vec4 ellipse; };
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };
layout(set=0,binding=0,std430) readonly buffer Samples { Sample v[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Instances { Instance v[]; } instances;

layout(set=0,binding=3,std430) buffer Projected { Projection v[]; } projected;
layout(set=0,binding=4,std430) buffer Depth { uint v[]; } depths;
layout(set=0,binding=5,std430) buffer Winner { uint v[]; } winners;
layout(set=0,binding=6,std430) readonly buffer Parameters {
    vec4 eye; vec4 right; vec4 up; vec4 forward; vec4 lens; ivec4 counts;
    vec4 light; vec4 light_color; vec4 ambient; vec4 options;
    vec4 shadow_right; vec4 shadow_up; vec4 shadow_forward;
    vec4 iris; vec4 wall; vec4 settings;
} parameters;
layout(set=0,binding=7,std430) buffer Accumulated { Accumulator v[]; } accumulated;
layout(rgba32f,set=0,binding=8) uniform image2D diffuse_image;
layout(rgba32f,set=0,binding=9) uniform image2D specular_image;
layout(rgba32f,set=0,binding=11) uniform image2D output_image;

layout(set=0,binding=13,std430) buffer Shadow { uint v[]; } shadow;
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;

layout(set=0,binding=14,std430) readonly buffer BenchData {uvec4 header;vec4 v[];} bench;
layout(rgba32f,set=0,binding=15) uniform readonly image2D field_irradiance;
layout(set=0,binding=16,std430) readonly buffer SurfaceLights {uvec4 header;vec4 values[];} surface_lights;
layout(set=0,binding=18,std430) readonly buffer Emission {vec4 v[];} emission;
vec3 lie_position(uint node){return bench.v[24u+node*3u].xyz;}
float lie_area(uint node){return bench.v[24u+node*3u].w;}
vec3 lie_normal(uint node){return bench.v[24u+node*3u+1u].xyz;}
uvec2 lie_group(uint node){return uvec2(bench.v[24u+node*3u+2u].xy);}
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
// Same point-source units, distance floor, range window and normalized power
// as the finite-patch field. No second emitter budget and no invented relief.
vec3 lie_surface_unoccluded(uint l,vec3 world,vec3 normal) {
    vec4 source=surface_lights.values[l*2u],power=surface_lights.values[l*2u+1u];
    vec3 delta=source.xyz-world;float d2=dot(delta,delta);
    if(d2<=1e-10 || source.w<=0.)return vec3(0);
    float cosine=max(dot(normal,delta*inversesqrt(d2)),0.);
    float fade=pow(max(0.,1.-pow(sqrt(d2)/source.w,4.)),2.);
    return power.rgb*(cosine*fade/(4.*PI*max(d2,power.w)));
}
// Finite-patch visibility/transmittance gates the local direct response.
// Contact-only mode cannot brighten. Detail mode redistributes direct light
// locally; its image-space integral is not a certified finite-area quadrature.

// Relative total RGB power: an isotropic point has gain 1. A one-sided
// Lambert emitter has intensity Phi*cos(theta)/PI, hence gain 4*cos.
float lie_emitter_gain(vec4 shape,vec3 from_source) {
    if(shape.w<.5)return 1.;
    float d2=dot(from_source,from_source);
    return d2>1e-20?4.*max(dot(shape.xyz,from_source*inversesqrt(d2)),0.):0.;
}

vec2 project(vec3 p,vec3 eye,vec3 right,vec3 up,vec3 forward,float tangent,vec2 size) {
    vec3 d=p-eye;float z=dot(d,forward);
    return vec2((dot(d,right)/(z*tangent)+1)*.5,(1-dot(d,up)/(z*tangent))*.5)*size;
}





float bench_visibility(uint light,vec3 p,vec3 geometric_normal) {
    vec3 d=p-surface_lights.values[light*2u].xyz;float z=dot(d,bench.v[light*3u+2u].xyz);
    if(z<=.001) return 1;
    vec2 uv=project(p,surface_lights.values[light*2u].xyz,bench.v[light*3u+0u].xyz,bench.v[light*3u+1u].xyz,bench.v[light*3u+2u].xyz,1.25,vec2(SHADOW_SIZE));
    if(any(lessThan(uv,vec2(1))) || any(greaterThan(uv,vec2(SHADOW_SIZE-2)))) return 1;
    float receiver_plane=dot(geometric_normal,d);
    if(abs(receiver_plane)<1e-7) return 1;
    vec2 gradient=vec2(2*1.25*dot(geometric_normal,bench.v[light*3u+0u].xyz),-2*1.25*dot(geometric_normal,bench.v[light*3u+1u].xyz))/(float(SHADOW_SIZE)*receiver_plane);
    float result=0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        ivec2 q=clamp(ivec2(uv)+ivec2(x,y),ivec2(0),ivec2(SHADOW_SIZE-1));
        float stored=uintBitsToFloat(shadow.v[light*uint(SHADOW_SIZE*SHADOW_SIZE)+uint(q.y*SHADOW_SIZE+q.x)]);
        // PCF taps refer to different rays. The receiver depth must follow
        // its plane at each tap; a constant center depth creates bands.
        float receiver_depth=1.0/(1.0/z+dot(gradient,vec2(q)+.5-uv));
        result+=(receiver_depth<=0 || receiver_depth<=stored+parameters.options.z)?1.0:0.0;
    }
    return result/9;
}








void main() {
    uint i=gl_GlobalInvocationID.x,pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=4;
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {imageStore(diffuse_image,xy,vec4(0));imageStore(specular_image,xy,vec4(0));return;}
        Projection point=projected.v[owner];
        Accumulator acc=accumulated.v[i];float weight=max(float(acc.color_weight.w),1);
        vec3 base=vec3(acc.color_weight.xyz)/weight;
        vec3 n=normalize(vec3(acc.normal_roughness.xyz)/weight*2-1);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        Sample source=samples.v[uint(point.gradient.w)];
        uint node=uint(source.attributes.y)+uint(instances.v[uint(point.gradient.z)].meta.x);
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++) {
            vec3 E=lie_surface_unoccluded(l,p,n)*lie_emitter_gain(emission.v[l],p-surface_lights.values[l*2u].xyz);
            direct+=E*bench_visibility(l,p+point.geometry.xyz*parameters.options.z*.45,point.geometry.xyz);
        }
        imageStore(diffuse_image,xy,vec4(base*direct/PI,1));
        imageStore(specular_image,xy,vec4(base*bench_indirect(p,node)/PI,1));
        return;
    }
    if(stage==6) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Accumulator acc=accumulated.v[i];vec3 base=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1);
        vec3 direct=imageLoad(diffuse_image,xy).rgb,indirect=imageLoad(specular_image,xy).rgb;
        int mode=int(parameters.settings.w);
        imageStore(output_image,xy,vec4(max(mode==1?direct:mode==2?indirect:direct+indirect,vec3(0)),1));
    }

}
