#[compute]
#version 450
// LIE-07 experimental continuous GPU compute pipeline.
// One dispatch pipeline, five ordered stages separated by compute barriers:
// 0 clear; 1 project all input source pixels; 2 atomic closest depth;
// 3 confidence-weighted RGB accumulation; 4 resolve to RGBA32F GPU image.
// This intentionally does not claim zero-copy Godot viewport integration.
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer Samples { vec4 points[]; } samples;
layout(set=0,binding=1,std430) readonly buffer Colors { vec4 rgba[]; } colors;
layout(set=0,binding=2,std430) readonly buffer Attributes {
    // x=view index 0..3; y=normal confidence; z=angular confidence.
    vec4 values[];
} attrs;
layout(set=0,binding=3,std430) readonly buffer Cameras {
    // TEN vec4 per source view (same layout as LIE-06 project_samples.glsl):
    // 0 origin, 1 right, 2 up, 3 forward; 4 target origin,
    // 5 target right, 6 target up, 7 target forward,
    // 8 ortho scale, source near, source far, unused,
    // 9 target tan_half_fov, aspect, near, far.
    vec4 data[];
} cameras;
layout(set=0,binding=4,std430) buffer Projected { vec4 positions[]; } projected;
layout(set=0,binding=5,std430) buffer Depth { uint encoded[]; } depths;
layout(set=0,binding=6,std430) buffer Accumulation { uvec4 rgba_weight[]; } sums;
layout(set=0,binding=7,std430) readonly buffer Config {
    // x=target width, y=target height, z=splat footprint 1 or 2.
    ivec4 dims;
} config;
layout(rgba32f,set=0,binding=8) uniform writeonly image2D target_image;
layout(push_constant,std430) uniform Phase { uint stage; } phase;

const float TOLERANCE_METERS=0.07;
const float FIXED_SCALE=4096.0;

uint target_count() {
    return uint(max(config.dims.x,0)*max(config.dims.y,0));
}
bool usable(uint i) {
    if(i>=uint(samples.points.length()) || i>=uint(colors.rgba.length())
        || i>=uint(attrs.values.length())) return false;
    if(samples.points[i].w<0.5 || colors.rgba[i].a<0.5) return false;
    float w=clamp(attrs.values[i].y,0.0,1.0)*clamp(attrs.values[i].z,0.0,1.0);
    return uint(round(w*FIXED_SCALE))>0u;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint pixel_count=target_count();
    if(phase.stage==0u) {
        if(i<pixel_count) {
            depths.encoded[i]=0x7f7fffffu;
            sums.rgba_weight[i]=uvec4(0u);
        }
        return;
    }
    if(phase.stage==4u) {
        if(i>=pixel_count) return;
        uvec4 acc=sums.rgba_weight[i];
        vec4 output_pixel=acc.w>0u
            ? vec4(vec3(acc.xyz)/float(acc.w),1.0)
            : vec4(0.0);
        ivec2 xy=ivec2(int(i)%config.dims.x,int(i)/config.dims.x);
        imageStore(target_image,xy,output_pixel);
        return;
    }
    if(i>=uint(samples.points.length())) return;
    if(phase.stage==1u) {
        projected.positions[i]=vec4(0.0);
        if(!usable(i)) return;
        int view=int(round(attrs.values[i].x));
        if(view<0 || view>3 || (view*10+9)>=cameras.data.length()) return;
        int b=view*10;
        vec4 s=samples.points[i];
        vec4 metrics=cameras.data[b+8];
        vec4 lens=cameras.data[b+9];
        float z=mix(metrics.y,metrics.z,clamp(s.z,0.0,1.0));
        vec3 world=cameras.data[b+0].xyz
            +(s.x-0.5)*metrics.x*cameras.data[b+1].xyz
            +(0.5-s.y)*metrics.x*cameras.data[b+2].xyz
            +z*cameras.data[b+3].xyz;
        vec3 rel=world-cameras.data[b+4].xyz;
        float depth=dot(rel,cameras.data[b+7].xyz);
        if(isnan(depth) || isinf(depth) || depth<lens.z || depth>lens.w
            || lens.x<=0.0 || lens.y<=0.0) return;
        float ndc_x=dot(rel,cameras.data[b+5].xyz)/(depth*lens.x*lens.y);
        float ndc_y=dot(rel,cameras.data[b+6].xyz)/(depth*lens.x);
        if(isnan(ndc_x) || isnan(ndc_y) || isinf(ndc_x) || isinf(ndc_y)
            || abs(ndc_x)>1.0 || abs(ndc_y)>1.0) return;
        projected.positions[i]=vec4(
            (ndc_x+1.0)*0.5*float(config.dims.x),
            (1.0-ndc_y)*0.5*float(config.dims.y),
            depth,1.0);
        return;
    }
    if(!usable(i)) return;
    vec4 p=projected.positions[i];
    if(p.w<0.5 || isnan(p.z) || isinf(p.z) || p.z<=0.0) return;
    uint depth_bits=floatBitsToUint(p.z);
    uint w=uint(round(clamp(attrs.values[i].y,0.0,1.0)
        *clamp(attrs.values[i].z,0.0,1.0)*FIXED_SCALE));
    int splat=clamp(config.dims.z,1,2);
    for(int oy=0;oy<splat;oy++) {
        for(int ox=0;ox<splat;ox++) {
            int x=int(floor(p.x))+ox;
            int y=int(floor(p.y))+oy;
            if(x<0 || y<0 || x>=config.dims.x || y>=config.dims.y) continue;
            uint idx=uint(y*config.dims.x+x);
            if(phase.stage==2u) {
                // IEEE754 positive float bits preserve depth ordering.
                atomicMin(depths.encoded[idx],depth_bits);
            } else if(phase.stage==3u) {
                float nearest=uintBitsToFloat(depths.encoded[idx]);
                if(abs(nearest-p.z)>TOLERANCE_METERS) continue;
                // Non-HDR RGBA [0..1]. Fixed-point integer atomics avoid
                // requiring unsupported mobile float atomic extensions.
                vec3 c=clamp(colors.rgba[i].rgb,vec3(0.0),vec3(1.0));
                uvec3 contribution=uvec3(round(c*float(w)));
                atomicAdd(sums.rgba_weight[idx].x,contribution.x);
                atomicAdd(sums.rgba_weight[idx].y,contribution.y);
                atomicAdd(sums.rgba_weight[idx].z,contribution.z);
                atomicAdd(sums.rgba_weight[idx].w,w);
            }
        }
    }
}
