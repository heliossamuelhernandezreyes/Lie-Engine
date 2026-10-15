#[compute]
#version 450
layout(local_size_x=64) in;
struct Projection {vec4 world;vec4 normal;vec4 screen;vec4 gradient;vec4 geometry;vec4 ellipse;};
layout(set=0,binding=0,std430) readonly buffer Inputs {vec4 values[];} source;
layout(set=0,binding=1,std430) buffer Results {vec4 values[];} result;
layout(push_constant,std430) uniform Options {uvec4 counts;} options;
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
// Conservative row intervals for the SAME projected ellipse and pixel grid.
// Final covered() and all depth/ownership rules remain authoritative.
ivec2 lie_splat_row(Projection p,ivec2 center,int y,int bound) {
    float dy=float(y)+.5-p.screen.y;
    float A=p.ellipse.x,B=p.ellipse.y,C=p.ellipse.z;
    float cross_section=1.-(C-B*B/A)*dy*dy;
    if(A<=0. || isnan(cross_section) || isinf(cross_section))return ivec2(center.x-bound,center.x+bound);
    // A one-pixel guard on both ends preserves floating-point boundary cases.
    // Even a slightly negative section receives a conservative candidate.
    float span=sqrt(max(cross_section,0.)/A);
    float middle=p.screen.x-B*dy/A-.5;
    return ivec2(max(center.x-bound,int(floor(middle-span))-1),
                 min(center.x+bound,int(ceil(middle+span))+1));
}

void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=options.counts.x)return;
    uint at=i*5u;vec4 albedo=source.values[at],view=source.values[at+1u],light=source.values[at+2u],normal=source.values[at+3u],config=source.values[at+4u];
    float rough=lie_filtered_roughness(albedo.w,config.x,config.y>.5);
    result.values[i]=vec4(lie_opaque_brdf(albedo.rgb,rough,config.z,config.w,normalize(normal.xyz),lie_opaque_direction(view.xyz),lie_opaque_direction(light.xyz)),rough);
}
