#[compute]
#version 450
// LIE-08 composite: persistent LIE-07 output texture -> real Godot render buffer.
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform image2D scene_color;
layout(rgba32f,set=0,binding=1) readonly uniform image2D lie_image;
layout(push_constant,std430) uniform Params {
    ivec2 viewport_size;
    ivec2 padding;
} pc;

void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,pc.viewport_size))) return;
    vec2 uv=(vec2(p)+vec2(0.5))/vec2(pc.viewport_size);
    ivec2 native_size=imageSize(lie_image);
    ivec2 capture_pixel=clamp(ivec2(uv*vec2(native_size)),ivec2(0),native_size-ivec2(1));
    vec4 capture=imageLoad(lie_image,capture_pixel);
    if(capture.a<0.5) return; // preserve existing scene for uncovered pixels
    vec4 scene=imageLoad(scene_color,p);
    vec3 blended=mix(scene.rgb,capture.rgb,0.95);
    imageStore(scene_color,p,vec4(blended,1.0));
}
