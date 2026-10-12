#[compute]
#version 450
// Four-tap reconstruction at the final viewport. Each tap independently
// respects native depth; one-pixel edge coverage does not create ghost geometry.
layout(local_size_x=8,local_size_y=8) in;
layout(rgba16f,set=0,binding=0) uniform image2D scene_color;
layout(rgba32f,set=0,binding=1) readonly uniform image2D lie_image;
layout(set=0,binding=2) uniform sampler2D native_depth;
layout(set=0,binding=3,std430) readonly buffer LieDepth { uint values[]; } lie_depth;
layout(push_constant,std430) uniform Config { ivec4 dims; vec4 projection; ivec4 flags; } pc;

vec3 tap(ivec2 at,vec3 background,float scene_depth) {
    at=clamp(at,ivec2(0),pc.dims.zw-ivec2(1));
    vec4 capture=imageLoad(lie_image,at);
    float z=uintBitsToFloat(lie_depth.values[uint(at.y*pc.dims.z+at.x)]);
    if(capture.a<.5 || isnan(z) || isinf(z) || z<=0.0 || (scene_depth>0.0 && scene_depth+.003<z)) return background;
    return capture.rgb;
}
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(xy,pc.dims.xy))) return;
    vec2 uv=(vec2(xy)+vec2(.5))/vec2(pc.dims.xy);
    vec3 background=imageLoad(scene_color,xy).rgb;
    float raw=textureLod(native_depth,uv,0.0).x;
    vec4 m=pc.projection;
    float denominator=raw*m.z-m.x;
    float scene_depth=abs(denominator)>1e-7?-(m.y-raw*m.w)/denominator:0.0;
    if(pc.flags.x==0) {
        ivec2 at=ivec2(uv*vec2(pc.dims.zw));
        imageStore(scene_color,xy,vec4(tap(at,background,scene_depth),1)); return;
    }
    vec2 position=uv*vec2(pc.dims.zw)-vec2(.5);
    ivec2 base=ivec2(floor(position)); vec2 t=fract(position);
    vec3 a=mix(tap(base,background,scene_depth),tap(base+ivec2(1,0),background,scene_depth),t.x);
    vec3 b=mix(tap(base+ivec2(0,1),background,scene_depth),tap(base+ivec2(1,1),background,scene_depth),t.x);
    imageStore(scene_color,xy,vec4(mix(a,b,t.y),1));
}
