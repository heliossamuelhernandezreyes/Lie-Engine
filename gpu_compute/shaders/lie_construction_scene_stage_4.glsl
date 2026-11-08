#[compute]
#version 450
// LIE28: source RGB albedo and roughness captured without lighting.
// Geometric normals remain independent of material maps. No source mesh draw.
layout(local_size_x=64) in;
struct Sample { vec4 position_radius; vec4 normal_gray; vec4 attributes; vec4 albedo; vec4 support; };
struct Instance { vec4 x; vec4 y; vec4 z; vec4 origin; vec4 meta; vec4 tint; };
// 64-byte std430 record: offsets 0/12, 16/24, 32/44, 48/60.
struct Projection {
    vec3 normal; float depth;
    vec2 center; vec2 gradient;
    vec3 geometry; float owner;
    vec3 ellipse; float radius;
};
struct Accumulator { uvec4 color_weight; uvec4 normal_roughness; };

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


layout(rgba32f,set=0,binding=11) uniform image2D output_image;

layout(set=0,binding=13,std430) buffer Shadow { uint v[]; } shadow;
layout(push_constant,std430) uniform Phase { ivec4 value; } phase;
const float PI=3.141592653589793;
const uint EMPTY=0xffffffffu;
const int SHADOW_SIZE=512;
vec2 project(vec3 p,vec3 eye,vec3 right,vec3 up,vec3 forward,float tangent,vec2 size) {
    vec3 d=p-eye;float z=dot(d,forward);
    return vec2((dot(d,right)/(z*tangent)+1)*.5,(1-dot(d,up)/(z*tangent))*.5)*size;
}




float lambda(float cosine,float a2) {
    return .5*(sqrt(1+a2*max(1-cosine*cosine,0)/max(cosine*cosine,1e-8))-1);
}
float visibility(vec3 p,vec3 geometric_normal) {
    vec3 d=p-parameters.light.xyz;float z=dot(d,parameters.shadow_forward.xyz);
    if(z<=.001) return 1;
    vec2 uv=project(p,parameters.light.xyz,parameters.shadow_right.xyz,parameters.shadow_up.xyz,parameters.shadow_forward.xyz,1.25,vec2(SHADOW_SIZE));
    if(any(lessThan(uv,vec2(1))) || any(greaterThan(uv,vec2(SHADOW_SIZE-2)))) return 1;
    float receiver_plane=dot(geometric_normal,d);
    if(abs(receiver_plane)<1e-7) return 1;
    vec2 gradient=vec2(2*1.25*dot(geometric_normal,parameters.shadow_right.xyz),-2*1.25*dot(geometric_normal,parameters.shadow_up.xyz))/(float(SHADOW_SIZE)*receiver_plane);
    float result=0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        ivec2 q=clamp(ivec2(uv)+ivec2(x,y),ivec2(0),ivec2(SHADOW_SIZE-1));
        float stored=uintBitsToFloat(shadow.v[q.y*SHADOW_SIZE+q.x]);
        // PCF taps refer to different rays. The receiver depth must follow
        // its plane at each tap; a constant center depth creates bands.
        float receiver_depth=1.0/(1.0/z+dot(gradient,vec2(q)+.5-uv));
        result+=(receiver_depth<=0 || receiver_depth<=stored+parameters.options.z)?1.0:0.0;
    }
    return result/9;
}








// Shared field receipt; map ownership is validated against every source face.
layout(set=0,binding=16,std430) readonly buffer ConstructionFieldMap {uvec4 config;uvec2 v[];} field_map;
struct FieldPatch {vec4 center_area;vec4 normal_gray;vec4 material;};
layout(set=0,binding=17,std430) readonly buffer ConstructionPatches {FieldPatch v[];} field_patches;
layout(rgba32f,set=0,binding=18) uniform readonly image2D field_irradiance;
layout(set=0,binding=19,std430) readonly buffer SurfaceLights {uvec4 header;vec4 values[];} surface_lights;
uvec2 lie_group(uint node) {return field_map.v[field_map.config.x*6u+node];}
vec3 lie_position(uint node) {return field_patches.v[node].center_area.xyz;}
vec3 lie_normal(uint node) {return field_patches.v[node].normal_gray.xyz;}
float lie_area(uint node) {return field_patches.v[node].center_area.w;}
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
vec3 lie_surface_refined(vec3 old_direct,vec3 unoccluded,
                        vec3 coefficient,vec3 local_direct,float visibility,bool detail) {
    vec3 gate=vec3(0);
    for(int c=0;c<3;c++)if(unoccluded[c]>1e-20)gate[c]=clamp(old_direct[c]/unoccluded[c],0.,1.);
    vec3 direct=detail?coefficient*local_direct*gate:old_direct;
    return direct*visibility;
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

uvec2 construction_group(Projection point) {
    Instance inst=instances.v[uint(point.owner)];
    vec3 n=transpose(mat3(inst.x.xyz,inst.y.xyz,inst.z.xyz))*point.geometry;
    vec3 a=abs(n);uint axis=a.x>=a.y && a.x>=a.z?0u:a.y>=a.z?1u:2u;
    uint face=axis*2u+(n[axis]>=0.?0u:1u);
    return field_map.v[uint(point.owner)*6u+face];
}
vec3 construction_indirect(vec3 world,uvec2 group) {
    if((field_map.config.z&2u)==0u || group.y==0u)return vec3(0);
    float sum=lie_stencil_sum(world,group.x);if(sum<=0.)return vec3(0);
    vec3 result=vec3(0);int width=imageSize(field_irradiance).x;
    for(uint k=group.x;k<group.x+group.y;k++) {
        vec3 direct=vec3(0);
        for(uint l=0u;l<surface_lights.header.y;l++)direct+=surface_lights.values[16u+l*field_map.config.y+k].rgb;
        vec3 total=imageLoad(field_irradiance,ivec2(int(k)%width,int(k)/width)).rgb;
        result+=max(total-direct,vec3(0))*(lie_stencil_weight(world,group.x,k)/sum);
    }
    return result;
}
vec3 construction_light_gate(vec3 world,uvec2 group,uint light) {
    float sum=lie_stencil_sum(world,group.x);if(sum<=0.)return vec3(0);
    vec3 old_direct=vec3(0),unoccluded=vec3(0);
    for(uint k=group.x;k<group.x+group.y;k++) {
        float weight=lie_stencil_weight(world,group.x,k)/sum;
        old_direct+=surface_lights.values[16u+light*field_map.config.y+k].rgb*weight;
        unoccluded+=lie_surface_unoccluded(light,lie_position(k),lie_normal(k))*weight;
    }
    vec3 gate=vec3(0);for(int c=0;c<3;c++)if(unoccluded[c]>1e-20)gate[c]=clamp(old_direct[c]/unoccluded[c],0.,1.);
    return gate;
}
vec3 construction_field_radiance(Projection point,vec3 world,vec3 view,vec3 normal,vec3 base,float rough,float key_shadow) {
    uvec2 group=construction_group(point);vec3 result=base*(.96/PI)*construction_indirect(world,group);
    for(uint l=0u;l<surface_lights.header.y;l++) {
        vec4 lamp=surface_lights.values[l*2u],power=surface_lights.values[l*2u+1u];vec3 delta=lamp.xyz-world;float d2=dot(delta,delta);
        if(d2<=1e-10 || lamp.w<=0.)continue;
        vec3 direction=lie_opaque_direction(delta);if(dot(point.geometry,direction)<=0.)continue;
        float fade=pow(max(0.,1.-pow(sqrt(d2)/lamp.w,4.)),2.);
        vec3 visibility=l==field_map.config.w?vec3(key_shadow):construction_light_gate(world,group,l);
        vec3 li=power.rgb*(fade/(4.*PI*max(d2,power.w)))*visibility;
        result+=lie_opaque_brdf(base,rough,.04,1.,normal,view,direction)*max(dot(normal,direction),0.)*li;
    }
    return result;
}

void main() {
    uint i=gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_NumWorkGroups.x*gl_WorkGroupSize.x,pixels=uint(parameters.counts.z*parameters.counts.w);
    const int stage=4;
    if(i>=pixels) return;
    ivec2 xy=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    uint owner=winners.v[i];
    if(stage==4) {
        if(owner==EMPTY) {imageStore(output_image,xy,vec4(0));return;}
        Projection point=projected.v[owner];
        Accumulator acc=accumulated.v[i];float weight=max(float(acc.color_weight.w),1);
        vec3 base=vec3(acc.color_weight.xyz)/weight;
        vec3 n=normalize(vec3(acc.normal_roughness.xyz)/weight*2-1);
        vec2 uv=(vec2(xy)+.5)/vec2(parameters.counts.zw);
        vec3 ray=parameters.forward.xyz+parameters.right.xyz*((2*uv.x-1)*parameters.lens.x)+parameters.up.xyz*((1-2*uv.y)*parameters.lens.x);
        vec3 p=parameters.eye.xyz+ray*uintBitsToFloat(depths.v[i]),v=normalize(parameters.eye.xyz-p);
        vec3 delta=parameters.light.xyz-p;float distance2=max(dot(delta,delta),.0001);vec3 l=normalize(delta);
        float nl=dot(point.geometry,l)>0.?max(dot(n,l),0):0.,nv=max(dot(n,v),1e-5);
        float shadow_factor=parameters.options.x>.5?visibility(p+point.geometry*parameters.options.z*.45,point.geometry):1;
        vec3 li=parameters.light_color.rgb*parameters.light.w/(4*PI*distance2)*shadow_factor;
        float roughness=clamp(float(acc.normal_roughness.w)/weight*parameters.options.y,.15,.95),alpha=roughness*roughness,a2=alpha*alpha;
        vec3 coat_n=parameters.settings.y<.5?normalize(p-instances.v[int(point.owner)].origin.xyz):n;
        if(parameters.settings.y<.5) {roughness=.10;alpha=roughness*roughness;a2=alpha*alpha;}
        vec3 h=normalize(v+l);float nh=max(dot(coat_n,h),0),vh=max(dot(v,h),0),denom=nh*nh*(a2-1)+1;
        vec3 F=vec3(.04)+(vec3(1)-vec3(.04))*pow(1-vh,5);
        float D=a2/(PI*denom*denom),G=1/(1+lambda(nv,a2)+lambda(nl,a2));
        vec3 specular=li*F*D*G/(4*nv)*(nl>0?1.0:0.0);
        vec3 ambient=parameters.ambient.rgb*.12;
        vec3 irradiance=(vec3(1)-F)*(li*nl/PI+ambient);
        vec3 radiance=base*irradiance+specular;
        if((field_map.config.z&1u)!=0u)radiance=construction_field_radiance(point,p,v,n,base,roughness,shadow_factor)+base*ambient*.96;
        imageStore(output_image,xy,vec4(max(radiance,vec3(0)),1));return;
    }

}
