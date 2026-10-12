#[compute]
#version 450
// LIE-12: opaque capture color + native depth vs GPU surface depth. Not
// a blanket "native geometry always wins" overlay.
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform image2D scene_color;
layout(rgba32f,set=0,binding=1) readonly uniform image2D lie_image;
layout(set=0,binding=2) uniform sampler2D native_depth;
layout(set=0,binding=3,std430) readonly buffer LieDepth { uint encoded[]; } lie_depth;
layout(push_constant,std430) uniform Config {
    ivec4 dims;  // viewport width,height, lie width,height
    vec4 camera_projection; // m22,m23,m32,m33
} pc;

void main() {
    ivec2 p=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(p,pc.dims.xy))) return;
    vec2 uv=(vec2(p)+vec2(0.5))/vec2(pc.dims.xy);
    ivec2 index=clamp(ivec2(uv*vec2(pc.dims.zw)),ivec2(0),pc.dims.zw-ivec2(1));
    vec4 capture=imageLoad(lie_image,index);
    if(capture.a<0.5) return;
    uint index1=uint(index.y*pc.dims.z+index.x);
    float lie_z=uintBitsToFloat(lie_depth.encoded[index1]);
    if(isnan(lie_z) || isinf(lie_z) || lie_z<=0.0) return;
    float raw=textureLod(native_depth,uv,0.0).x;
    // Reconstruct signed view z from the ACTUAL Godot view projection,
    // including reverse-Z. No hard-coded near/far or NDC convention.
    vec4 m=pc.camera_projection;
    float denominator=raw*m.z-m.x;
    if(abs(denominator)>1e-7) {
        float scene_z=-(m.y-raw*m.w)/denominator;
        // If a raster surface is closer, it MUST remain in front.
        if(scene_z>0.0 && scene_z+0.025<lie_z) return;
    }
    // A valid captured opaque surface completely covers farther native color.
    imageStore(scene_color,p,vec4(capture.rgb,1.0));
}
