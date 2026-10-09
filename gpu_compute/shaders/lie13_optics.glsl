#[compute]
#version 450
// LIE-13 thin dielectric SPRITES. No source mesh drawing. Layer peeling
// writes separate images; displaced samples never read a live framebuffer.
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
struct Sprite { vec4 center_thickness; vec4 right_width; vec4 up_height; vec4 sigma_ior; vec4 animation; };
struct Light { vec4 position_radius; vec4 power; };
layout(rgba16f,set=0,binding=0) uniform image2D scene_color;
layout(rgba32f,set=0,binding=1) readonly uniform image2D input_color;
layout(rgba32f,set=0,binding=2) writeonly uniform image2D output_color;
layout(set=0,binding=3) uniform sampler2D native_depth;
layout(set=0,binding=4,std430) readonly buffer LieDepth { uint values[]; } lie_depth;
layout(rgba32f,set=0,binding=5) readonly uniform image2D lie_capture;
layout(set=0,binding=6,std430) readonly buffer Sprites { Sprite values[]; } sprites;
layout(set=0,binding=7,std430) readonly buffer Config {
    ivec4 dims; // optical width,height, sprite count, light count
    vec4 eye; vec4 right; vec4 up; vec4 forward;
    vec4 view; // tan fov/2, aspect, time, environment radiance scale
    vec4 projection; // Godot m22,m23,m32,m33
} cfg;
layout(set=0,binding=8,std430) readonly buffer Lights { Light values[]; } lights;
layout(rgba32f,set=0,binding=9) uniform image2D diagnostic;
layout(set=0,binding=10) uniform sampler2D normal_atlas;
layout(push_constant,std430) uniform Phase { ivec4 data; } phase;
const int LAYERS=4;

float native_z(vec2 uv) {
    float raw=textureLod(native_depth,uv,0.0).r;
    vec4 m=cfg.projection;
    float denominator=raw*m.z-m.x;
    if(abs(denominator)<1e-7) return 1e20;
    float z=-(m.y-raw*m.w)/denominator;
    return z>0.0?z:1e20;
}
float opaque_z(vec2 uv) {
    ivec2 p=clamp(ivec2(uv*vec2(imageSize(lie_capture))),ivec2(0),imageSize(lie_capture)-1);
    float z=native_z(uv);
    if(imageLoad(lie_capture,p).a>0.5) {
        float l=uintBitsToFloat(lie_depth.values[p.y*imageSize(lie_capture).x+p.x]);
        if(!isnan(l) && !isinf(l) && l>0.0) z=min(z,l);
    }
    return z;
}
vec3 ray(vec2 uv) {
    vec2 v=uv*2.0-1.0;
    return normalize(cfg.forward.xyz+cfg.right.xyz*v.x*cfg.view.x*cfg.view.y-cfg.up.xyz*v.y*cfg.view.x);
}
vec2 project(vec3 world) {
    vec3 d=world-cfg.eye.xyz;
    float z=dot(d,cfg.forward.xyz);
    return vec2(dot(d,cfg.right.xyz)/(z*cfg.view.x*cfg.view.y),-dot(d,cfg.up.xyz)/(z*cfg.view.x))*0.5+0.5;
}
vec4 background(vec2 uv) {
    ivec2 p=clamp(ivec2(uv*vec2(cfg.dims.xy)),ivec2(0),cfg.dims.xy-1);
    return imageLoad(input_color,p);
}
float fresnel(float ci, float eta, out float ct) {
    float s2=(1.0-ci*ci)/(eta*eta);
    if(s2>=1.0) { ct=0.0; return 1.0; }
    ct=sqrt(max(0.0,1.0-s2));
    float rs=(ci-eta*ct)/max(ci+eta*ct,1e-8);
    float rp=(eta*ci-ct)/max(eta*ci+ct,1e-8);
    return 0.5*(rs*rs+rp*rp);
}
vec3 reflected_radiance(vec3 position, vec3 direction) {
    // Explicit external environment, plus finite angular punctual highlights.
    // Screen-space tracing intentionally omitted; no off-screen scene claim.
    float horizon=clamp(direction.y*0.5+0.5,0.0,1.0);
    vec3 radiance=mix(vec3(0.07,0.09,0.13),vec3(0.6,0.75,1.0),horizon)*cfg.view.w;
    for(int k=0;k<cfg.dims.w;k++) {
        vec3 delta=lights.values[k].position_radius.xyz-position;
        float d2=max(dot(delta,delta),0.0025);
        float window=pow(max(0.0,1.0-pow(sqrt(d2)/lights.values[k].position_radius.w,4.0)),2.0);
        float disk=pow(max(dot(direction,normalize(delta)),0.0),256.0);
        radiance+=lights.values[k].power.rgb*window*disk/(12.5663706*d2);
    }
    return radiance;
}

void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(phase.data.x==2) {
        if(any(greaterThanEqual(p,imageSize(scene_color)))) return;
        vec2 uv=(vec2(p)+0.5)/vec2(imageSize(scene_color));
        vec4 color=background(uv);
        // Only covered optical pixels replace the native/captured opaque scene.
        if(color.a+0.0001<opaque_z(uv)) imageStore(scene_color,p,vec4(color.rgb,1.0));
        return;
    }
    if(any(greaterThanEqual(p,cfg.dims.xy))) return;
    vec2 uv=(vec2(p)+0.5)/vec2(cfg.dims.xy);
    if(phase.data.x==0) {
        ivec2 screen=clamp(ivec2(uv*vec2(imageSize(scene_color))),ivec2(0),imageSize(scene_color)-1);
        imageStore(output_color,p,vec4(imageLoad(scene_color,screen).rgb,opaque_z(uv)));
        imageStore(diagnostic,p,vec4(-1.0));
        return;
    }
    vec3 d=ray(uv);
    float distances[LAYERS]; int ids[LAYERS]; vec2 locals[LAYERS];
    for(int k=0;k<LAYERS;k++) { distances[k]=1e20; ids[k]=-1; }
    float base_z=opaque_z(uv);
    for(int i=0;i<cfg.dims.z;i++) {
        Sprite s=sprites.values[i];
        vec3 n=cross(s.right_width.xyz,s.up_height.xyz);
        float den=dot(d,n);
        if(abs(den)<1e-6) continue;
        float t=dot(s.center_thickness.xyz-cfg.eye.xyz,n)/den;
        float z=t*dot(d,cfg.forward.xyz);
        if(t<=0.1 || z>=base_z-0.0001) continue;
        vec3 local=cfg.eye.xyz+d*t-s.center_thickness.xyz;
        vec2 xy=vec2(dot(local,s.right_width.xyz)/s.right_width.w,dot(local,s.up_height.xyz)/s.up_height.w);
        if(any(greaterThan(abs(xy),vec2(1.0)))) continue;
        vec2 atlas_uv=vec2((xy.x*0.5+0.5+float(int(s.animation.x)))/3.0,xy.y*0.5+0.5);
        if(textureLod(normal_atlas,atlas_uv,0.0).a<=0.0) continue;
        for(int k=0;k<LAYERS;k++) {
            // Tie-break by material data, independently of insertion order.
            if(t<distances[k]) {
                for(int j=LAYERS-1;j>k;j--) { distances[j]=distances[j-1]; ids[j]=ids[j-1]; locals[j]=locals[j-1]; }
                distances[k]=t; ids[k]=i; locals[k]=xy; break;
            }
        }
    }
    int rank=phase.data.y;
    vec4 old=imageLoad(input_color,p);
    if(ids[rank]<0) { imageStore(output_color,p,old); return; }
    Sprite s=sprites.values[ids[rank]];
    vec2 xy=locals[rank];
    vec2 atlas_uv=vec2((xy.x*0.5+0.5+float(int(s.animation.x)))/3.0,xy.y*0.5+0.5);
    vec4 map=textureLod(normal_atlas,atlas_uv,0.0);
    vec3 plane_n=normalize(cross(s.right_width.xyz,s.up_height.xyz));
    vec3 tangent_n=map.xyz;
    if(int(s.animation.x)==1) {
        // Prescribed surface waves, not fluid simulation. The derivative drives
        // the normal; pixels never masquerade as displaced source meshes.
        float f=s.animation.z, a=s.animation.y, time=cfg.view.z;
        tangent_n=normalize(vec3(-a*f*cos(xy.x*f+time*1.7),-a*f*0.7*cos(xy.y*f-time*1.2),1.0));
    }
    vec3 n=normalize(s.right_width.xyz*tangent_n.x+s.up_height.xyz*tangent_n.y+plane_n*tangent_n.z);
    if(dot(n,d)>0.0) n=-n;
    float ci=clamp(-dot(n,d),0.0,1.0), ct;
    float f=fresnel(ci,s.sigma_ior.w,ct);
    float thickness=s.center_thickness.w*map.a;
    vec3 attenuation=exp(-s.sigma_ior.rgb*thickness/max(ct,1e-6));
    vec3 transmission=pow(1.0-f,2.0)*attenuation;
    vec3 reflection=vec3(f)+pow(1.0-f,2.0)*attenuation*attenuation*f;
    if(max(reflection.r,max(reflection.g,reflection.b))<1e-8 && min(transmission.r,min(transmission.g,transmission.b))>0.9999999) {
        imageStore(output_color,p,old);
        if(rank==0) imageStore(diagnostic,p,vec4(f,transmission));
        return;
    }
    vec3 position=cfg.eye.xyz+d*distances[rank];
    vec3 bent=refract(d,n,1.0/s.sigma_ior.w);
    vec3 displacement=(bent/max(ct,1e-6)-d/max(ci,1e-6))*thickness;
    vec2 displaced=project(position+d*max(0.01,thickness/max(ci,1e-6))+displacement);
    float z=dot(position-cfg.eye.xyz,cfg.forward.xyz);
    vec4 sample_color=background(displaced);
    // Prevent unrelated closer surfaces from leaking through refraction.
    bool valid=all(greaterThanEqual(displaced,vec2(0))) && all(lessThanEqual(displaced,vec2(1))) && sample_color.a>=z-0.0001;
    vec3 transmitted=valid?sample_color.rgb:old.rgb;
    vec3 radiance=reflected_radiance(position,reflect(d,n));
    vec3 color=transmission*transmitted+reflection*radiance;
    imageStore(output_color,p,vec4(color,z));
    if(rank==0) imageStore(diagnostic,p,vec4(f,transmission));
}
