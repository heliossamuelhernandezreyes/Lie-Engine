#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0) uniform sampler2D surface_world;
layout(set=0,binding=1) uniform sampler2D surface_normal;
layout(set=0,binding=2) uniform sampler2D surface_color;
layout(set=0,binding=3) uniform sampler2DArray shadow_maps;
layout(rgba32f,set=0,binding=4) uniform image2D output_image;
layout(rgba32f,set=0,binding=5) readonly uniform image2D field;
layout(set=0,binding=6,std430) readonly buffer Codes {vec4 v[];} codes;
layout(set=0,binding=7,std430) readonly buffer Lights {uvec4 header;vec4 v[];} lights;
layout(set=0,binding=8,std430) readonly buffer Groups {uvec4 header;uvec4 v[];} groups;
struct View {vec4 eye;vec4 right;vec4 up;vec4 forward;vec4 lens;};
layout(set=0,binding=9,std430) readonly buffer Views {View v[];} views;
layout(set=0,binding=10,std430) buffer NodeResponse {vec4 v[];} nodes;
layout(set=0,binding=11,std430) readonly buffer Emission {vec4 v[];} emission;
layout(set=0,binding=12,std430) readonly buffer Options {uvec4 flags;vec4 tuning;} options;
layout(push_constant,std430) uniform Push {ivec4 value;} push;
const float PI=3.141592653589793;
vec3 lie_position(uint node){return codes.v[node*3u].xyz;}
vec3 lie_normal(uint node){return codes.v[node*3u+1u].xyz;}
float lie_area(uint node){return codes.v[node*3u].w;}
uvec2 lie_group(uint node){return groups.header.x==0u?uvec2(node,1):groups.v[node].xy;}
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

// Opaque nonmetal appearance, in linear relative radiometric units.
// Host supplies directions AWAY from the surface and incident irradiance.
// GGX / height-correlated Smith, Schlick dielectric Fresnel; reciprocal
// two-sided Fresnel attenuation of the Lambert substrate. Single scattering.
// This is an authored material approximation, not measured coated transport.
vec3 lie_opaque_direction(vec3 delta) {
    // A source exactly on a receiver has zero incident irradiance. Keep its
    // direction finite as well: normalize(0) is undefined on GPU hardware.
    return delta*inversesqrt(max(dot(delta,delta),1e-20));
}
float lie_fresnel(float cosine,float f0) {
    float m=clamp(1.-cosine,0.,1.);float m2=m*m;
    return f0+(1.-f0)*m2*m2*m;
}
float lie_filtered_roughness(float roughness,float mean_length,bool filtered) {
    float r=clamp(roughness,.2,.98);
    float variance=filtered?clamp(1.-mean_length,0.,1.):0.;
    // Normal variance broadens the squared microfacet width. It never
    // changes the captured geometric normal, source color or visibility.
    return sqrt(sqrt(min(r*r*r*r+variance,1.)));
}
vec3 lie_opaque_brdf(vec3 albedo,float roughness,float f0,float survival,vec3 normal,vec3 view,vec3 light) {
    float nl=dot(normal,light),nv=dot(normal,view);
    if(nl<=1e-6 || nv<=1e-6)return vec3(0);
    vec3 half_sum=view+light;float h2=dot(half_sum,half_sum);
    if(h2<=1e-12)return vec3(0);
    vec3 h=half_sum*inversesqrt(h2);
    float nh=max(dot(normal,h),0.),vh=max(dot(view,h),0.);
    float alpha=roughness*roughness,a2=alpha*alpha;
    float denominator=nh*nh*(a2-1.)+1.;
    float D=a2/(3.141592653589793*denominator*denominator);
    // Algebraically equivalent to G2/(4*nl*nv); stable near grazing.
    float smith=2.*(nv*sqrt(a2+(1.-a2)*nl*nl)+nl*sqrt(a2+(1.-a2)*nv*nv));
    float specular=D*lie_fresnel(vh,f0)/max(smith,1e-12);
    float diffuse=(1.-lie_fresnel(nl,f0))*(1.-lie_fresnel(nv,f0))/3.141592653589793;
    return albedo*diffuse+vec3(specular*survival);
}

vec3 incident(uint l,vec3 p,vec3 n){
    vec4 source=lights.v[l*2u],power=lights.v[l*2u+1u];vec3 delta=source.xyz-p;
    float d2=dot(delta,delta);if(d2<=1e-10||source.w<=0.)return vec3(0);
    float cosine=max(dot(n,delta*inversesqrt(d2)),0.);
    float fade=pow(max(0.,1.-pow(sqrt(d2)/source.w,4.)),2.);
    vec4 shape=emission.v[l];float gain=shape.w<.5?1.:4.*max(dot(shape.xyz,-delta*inversesqrt(d2)),0.);
    return power.rgb*(cosine*fade*gain/(4.*PI*max(d2,power.w)));
}
float visibility(uint l,vec3 p,vec3 normal){
    if(options.flags.x==0u)return 1.;
    vec3 d=p-lights.v[l*2u].xyz;vec3 ad=abs(d);
    int axis=ad.x>=ad.y&&ad.x>=ad.z?0:ad.y>=ad.z?1:2;
    int face=axis*2+(d[axis]>=0.?0:1);int layer=int(l)*6+face;
    View view=views.v[1+layer];
    vec3 q=p+normal*options.tuning.x-view.eye.xyz;
    float z=dot(q,view.forward.xyz),near=view.lens.x,far=view.lens.y;
    if(z<=near||z>=far)return 1.;
    vec2 uv=vec2(dot(q,view.right.xyz),-dot(q,view.up.xyz))/z*.5+.5;
    float depth=far/(far-near)-far*near/((far-near)*z);
    depth-=far*near/(far-near)*options.tuning.y/(z*z);
    ivec2 size=textureSize(shadow_maps,0).xy;
    ivec2 pixel=ivec2(uv*vec2(size));float visible=0.;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
        ivec2 at=clamp(pixel+ivec2(x,y),ivec2(0),size-1);
        visible+=depth<=texelFetch(shadow_maps,ivec3(at,layer),0).r?1.:0.;
    }
    return visible/9.;
}
void main(){
    uint i=gl_GlobalInvocationID.x+gl_WorkGroupID.y*gl_NumWorkGroups.x*64u;
    uint count=lights.header.x,L=lights.header.y;
    if(push.value.x==0){
        if(i>=count)return;
        vec3 total_direct=vec3(0);
        for(uint l=0u;l<L;l++){
            vec3 unoccluded=incident(l,lie_position(i),lie_normal(i));
            vec3 coarse=lights.v[16u+l*count+i].rgb;
            nodes.v[count+l*count+i]=vec4(unoccluded,0.);
            total_direct+=coarse;
        }
        nodes.v[i]=vec4(max(imageLoad(field,ivec2(int(i),0)).rgb-total_direct,vec3(0)),0.);
        return;
    }
    ivec2 size=imageSize(output_image);if(i>=uint(size.x*size.y))return;
    ivec2 pixel=ivec2(int(i)%size.x,int(i)/size.x);
    vec4 hit=texelFetch(surface_world,pixel,0);
    if(hit.w<.5){imageStore(output_image,pixel,vec4(0));return;}
    uint node=uint(round(hit.w))-1u;if(node>=count){imageStore(output_image,pixel,vec4(1,0,1,1));return;}
    vec4 material=texelFetch(surface_color,pixel,0),nr=texelFetch(surface_normal,pixel,0);
    vec3 n=normalize(nr.xyz),view=lie_opaque_direction(views.v[0].eye.xyz-hit.xyz);
    uvec2 group=lie_group(node);float sum=group.y==1u?1.:lie_stencil_sum(hit.xyz,node);
    float weights[9];vec3 indirect=vec3(0);float survival=0.;
    for(uint k=0u;k<group.y;k++){
        uint id=group.x+k;float w=group.y==1u?1.:lie_stencil_weight(hit.xyz,node,id)/max(sum,1e-30);
        weights[k]=w;float retain=1.-clamp(codes.v[id*3u+2u].w,0.,1.);
        survival+=w*retain;indirect+=w*retain*nodes.v[id].rgb;
    }
    vec3 color=material.rgb*indirect/PI;
    for(uint l=0u;l<L;l++){
        vec3 coarse=vec3(0),unoccluded=vec3(0);
        for(uint k=0u;k<group.y;k++){
            uint id=group.x+k;coarse+=weights[k]*lights.v[16u+l*count+id].rgb;
            unoccluded+=weights[k]*nodes.v[count+l*count+id].rgb;
        }
        vec3 gate=vec3(0);for(int c=0;c<3;c++)if(unoccluded[c]>1e-20)gate[c]=clamp(coarse[c]/unoccluded[c],0.,1.);
        vec3 direction=lie_opaque_direction(lights.v[l*2u].xyz-hit.xyz);
        vec3 response=options.flags.y!=0u?lie_opaque_brdf(material.rgb*survival,nr.w,.04,survival,n,view,direction):material.rgb*survival/PI;
        color+=max(response,vec3(0))*incident(l,hit.xyz,n)*gate*visibility(l,hit.xyz,n);
    }
    imageStore(output_image,pixel,vec4(max(color,vec3(0)),material.a));
}
