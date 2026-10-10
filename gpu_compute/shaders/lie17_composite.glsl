#[compute]
#version 450
// Contrast-guided filtering merged into the final reconstruction pass.
// Lie is immutable input; never sample the scene image another thread writes.
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
vec3 sample_at(vec2 pos,vec3 background,float scene_depth) {
    ivec2 base=ivec2(floor(pos)); vec2 t=fract(pos);
    vec3 a=mix(tap(base,background,scene_depth),tap(base+ivec2(1,0),background,scene_depth),t.x);
    vec3 b=mix(tap(base+ivec2(0,1),background,scene_depth),tap(base+ivec2(1,1),background,scene_depth),t.x);
    return mix(a,b,t.y);
}
float perceptual_luma(vec3 c) { return sqrt(max(dot(c,vec3(.2126,.7152,.0722)),0.0)); }
vec3 edge_filter(vec2 pos,vec3 center,vec3 background,float scene_depth) {
    float nw=perceptual_luma(sample_at(pos+vec2(-1,-1),background,scene_depth));
    float ne=perceptual_luma(sample_at(pos+vec2(1,-1),background,scene_depth));
    float sw=perceptual_luma(sample_at(pos+vec2(-1,1),background,scene_depth));
    float se=perceptual_luma(sample_at(pos+vec2(1,1),background,scene_depth));
    float m=perceptual_luma(center);
    float low=min(m,min(min(nw,ne),min(sw,se)));
    float high=max(m,max(max(nw,ne),max(sw,se)));
    if(high-low<max(.04,high*.125)) return center;
    // Follow the contour rather than blurring indiscriminately across it.
    // Flat gradients and isolated texels have no stable direction; retain them.
    vec2 direction=vec2(sw+se-nw-ne,nw+sw-ne-se);
    if(dot(direction,direction)<1e-8) return center;
    float regularizer=max((nw+ne+sw+se)*.03125,.0078125);
    direction=clamp(direction/(min(abs(direction.x),abs(direction.y))+regularizer),vec2(-2),vec2(2));
    vec3 narrow=.5*(sample_at(pos-direction/6.0,background,scene_depth)+sample_at(pos+direction/6.0,background,scene_depth));
    vec3 wide=.5*narrow+.25*(sample_at(pos-direction*.5,background,scene_depth)+sample_at(pos+direction*.5,background,scene_depth));
    float luminance=perceptual_luma(wide);
    return luminance<low || luminance>high?narrow:wide;
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
    vec3 color=sample_at(position,background,scene_depth);
    if(pc.flags.y!=0) color=edge_filter(position,color,background,scene_depth);
    imageStore(scene_color,xy,vec4(color,1));
}
