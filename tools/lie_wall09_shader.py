"""Adapter: existing source reconstruction + reusable surface-light kernels."""
from pathlib import Path
from lie_wall07_shader import generate as baseline
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=baseline()
    header='''
layout(set=0,binding=22,std430) readonly buffer SurfaceOptions { uvec4 flags; vec4 metric; } surface_options;
layout(set=0,binding=23,std430) readonly buffer SurfaceLights { uvec4 header; vec4 values[]; } surface_lights;
// 32 bytes per accepted recovery record instead of a full-frame world atlas.
struct RecoverySurface {vec4 world;vec4 normal;};
layout(set=0,binding=24,std430) buffer RecoverySurfaces { RecoverySurface values[]; } recovery_surfaces;
vec3 lie_surface_ray(vec2 screen) {
    vec2 uv=screen/vec2(parameters.counts.zw);
    return parameters.forward.xyz+parameters.right.xyz*((2.*uv.x-1.)*parameters.lens.x)+
        parameters.up.xyz*((1.-2.*uv.y)*parameters.lens.x);
}
vec3 lie_surface_world(Projection p,vec2 screen) {
    return parameters.eye.xyz+lie_surface_ray(screen)*pixel_depth(p,screen);
}
vec2 lie_surface_project(vec3 world) {
    vec3 d=world-parameters.eye.xyz;float z=dot(d,parameters.forward.xyz);
    if(z<=parameters.lens.z)return vec2(-1e9);
    vec2 uv=vec2(dot(d,parameters.right.xyz),-dot(d,parameters.up.xyz))/(z*parameters.lens.x);
    return (uv*.5+.5)*vec2(parameters.counts.zw);
}
bool lie_surface_observed(ivec2 q,out vec3 point,out vec3 normal) {
    if(!inside(q))return false;
    uint owner=winners.v[uint(q.y*parameters.counts.z+q.x)];
    if(owner==EMPTY)return false;
    Projection p=projected.v[owner];point=lie_surface_world(p,vec2(q)+.5);
    normal=normalize(p.normal.xyz);return true;
}
'''
    header+=(ROOT/'gpu_compute/shaders/lib/lie_contact_surface.glslinc').read_text()
    header+=(ROOT/'gpu_compute/shaders/lib/lie_surface_direct.glslinc').read_text()
    header+='''
void lie_resolve_surface(uint i) {
    if(i>=uint(parameters.counts.z*parameters.counts.w))return;
    if(surface_options.flags.x==0u && surface_options.flags.y==0u)return;
    ivec2 q=ivec2(int(i)%parameters.counts.z,int(i)/parameters.counts.z);
    vec4 base=imageLoad(specular_image,q);if(base.a<.5)return;
    uint owner=winners.v[i],slot=recovery_map.values[i];
    vec3 world,normal;vec3 coefficients[9];for(int k=0;k<9;k++)coefficients[k]=vec3(0);
    uvec2 group;
    if(owner!=EMPTY) {
        Projection p=projected.v[owner];uint node=projection_node(p);group=lie_group(node);
        world=lie_surface_world(p,vec2(q)+.5);normal=normalize(p.normal.xyz);
        Accumulator acc=accumulated.v[i];
        vec3 albedo=vec3(acc.color_weight.xyz)/max(float(acc.color_weight.w),1.);
        vec3 mean_normal=vec3(acc.normal_roughness.xyz)/max(float(acc.color_weight.w),1.)*2.-1.;
        if(dot(mean_normal,mean_normal)>1e-8 && dot(normalize(mean_normal),normal)>.9)normal=normalize(mean_normal);
        float sum=group.y==1u?1.:lie_stencil_sum(p.world.xyz,node);
        for(uint k=0u;k<group.y;k++) {
            float w=group.y==1u?1.:lie_stencil_weight(p.world.xyz,node,group.x+k)/max(sum,1e-30);
            coefficients[k]=albedo*(w/PI);
        }
    } else {
        // An overflow/unwitnessed hole stays on the accepted baseline path.
        if(slot==EMPTY || slot==0u || slot>MAX_RECOVERY)return;
        Recovery record=recovery.values[slot-1u];group=record.info.xy;
        RecoverySurface surface=recovery_surfaces.values[slot-1u];
        world=surface.world.xyz;normal=surface.normal.xyz;
        for(uint k=0u;k<group.y;k++)coefficients[k]=record.coefficients[k].rgb;
    }
    vec3 coefficient=vec3(0);
    for(uint k=0u;k<group.y;k++) {
        float absorption=clamp(injected_material_codes.values[(group.x+k)*3u+2u].w,0.,1.);
        coefficients[k]*=1.-absorption;coefficient+=coefficients[k];
    }
    vec3 old_total=vec3(0),new_total=vec3(0);
    for(uint l=0u;l<surface_lights.header.y;l++) {
        if(max(surface_lights.values[l*2u+1u].r,max(surface_lights.values[l*2u+1u].g,surface_lights.values[l*2u+1u].b))<=0.)continue;
        vec3 old_direct=vec3(0),unoccluded=vec3(0);
        for(uint k=0u;k<group.y;k++) {
            if(max(coefficients[k].r,max(coefficients[k].g,coefficients[k].b))<=0.)continue;
            uint node=group.x+k;
            old_direct+=coefficients[k]*surface_lights.values[16u+l*surface_lights.header.x+node].rgb;
            unoccluded+=coefficients[k]*lie_surface_unoccluded(l,lie_position(node),lie_normal(node));
        }
        float visibility=1.;
        if(surface_options.flags.x!=0u && max(old_direct.r,max(old_direct.g,old_direct.b))>0.)
            visibility=lie_contact_visibility(world,normal,surface_lights.values[l*2u].xyz,
                surface_options.metric.x,surface_options.metric.y,int(surface_options.flags.z));
        vec3 local_direct=lie_surface_unoccluded(l,world,normal);
        old_total+=old_direct;
        new_total+=lie_surface_refined(old_direct,unoccluded,coefficient,local_direct,visibility,surface_options.flags.y!=0u);
    }
    imageStore(specular_image,q,vec4(max(base.rgb-old_total,vec3(0))+new_total,base.a));
}
'''
    s=replace(s,'void main() {',header+'\nvoid main() {')
    # Main's linear index flattens the existing two-dimensional dispatch.
    marker='int stage=phase.value.x;'
    s=replace(s,marker,marker+'\n    if(stage==10) {lie_resolve_surface(i);return;}')
    s=replace(s,'uint chosen_group=EMPTY;','uint chosen_group=EMPTY;uint chosen_owner=EMPTY;')
    s=replace(s,'chosen_normal=normalize(pr.normal.xyz);','chosen_normal=normalize(pr.normal.xyz);chosen_owner=owner;')
    s=replace(s,'uint photo_group=EMPTY;','uint photo_group=EMPTY;uint photo_owner=EMPTY;')
    s=replace(s,'photo_normal=normalize(pr.normal.xyz);','photo_normal=normalize(pr.normal.xyz);photo_owner=owner;')
    s=replace(s,'chosen_normal=photo_normal;','chosen_normal=photo_normal;chosen_owner=photo_owner;')
    s=replace(s,'recovery.values[slot]=r;recovery_map.values[i]=slot+1u;','''recovery.values[slot]=r;recovery_map.values[i]=slot+1u;
                    RecoverySurface surface;
                    surface.world=vec4(lie_surface_world(projected.v[chosen_owner],vec2(q)+.5),1);
                    surface.normal=vec4(chosen_normal,0);recovery_surfaces.values[slot]=surface;''')
    return s
if __name__=='__main__':(ROOT/'gpu_compute/shaders/lie_wall09_surface.glsl').write_text(generate())
