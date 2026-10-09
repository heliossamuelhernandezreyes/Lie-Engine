#[compute]
#version 450
// LIE-06 isolated Vulkan GPU coordinate reprojection proof.
// Source samples: (u,v,normalized_orthographic_depth,valid).
// Output: (x_screen_pixels,y_screen_pixels,camera_linear_z,valid).
// Projection is a real GPU calculation, not CPU projection in disguise.
// A production scatter/depth-buffer and renderer integration are NOT here.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer Samples {
    vec4 sample[];
} inputs;
layout(set=0,binding=1,std430) readonly buffer CaptureAndCamera {
    // 0 source camera origin, 1 source right, 2 source up,
    // 3 source forward into object, 4 target camera origin,
    // 5 target right, 6 target up, 7 target forward,
    // 8 (ortho_scale,source_near,source_far,output_width),
    // 9 (target_tan_half_vertical_fov,target_aspect,target_near,target_far)
    vec4 data[];
} params;
layout(set=0,binding=2,std430) buffer Projected {
    vec4 result[];
} output_data;

void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=uint(inputs.sample.length()) || i>=uint(output_data.result.length())) {
        return;
    }
    vec4 sample_data=inputs.sample[i];
    if(sample_data.w<0.5) {
        output_data.result[i]=vec4(0.0);
        return;
    }
    vec4 metrics=params.data[8];
    vec4 target=params.data[9];
    float meters=mix(metrics.y,metrics.z,clamp(sample_data.z,0.0,1.0));
    vec3 world_point=params.data[0].xyz
        +(sample_data.x-0.5)*metrics.x*params.data[1].xyz
        +(0.5-sample_data.y)*metrics.x*params.data[2].xyz
        +meters*params.data[3].xyz;
    vec3 relative=world_point-params.data[4].xyz;
    float depth=dot(relative,params.data[7].xyz);
    if(depth<target.z || depth>target.w) {
        output_data.result[i]=vec4(0.0);
        return;
    }
    float x_ndc=dot(relative,params.data[5].xyz)
        /max(0.00001,depth*target.x*target.y);
    float y_ndc=dot(relative,params.data[6].xyz)
        /max(0.00001,depth*target.x);
    float half_width=metrics.w*0.5;
    float half_height=half_width/target.y;
    float valid=float(abs(x_ndc)<=1.0 && abs(y_ndc)<=1.0);
    output_data.result[i]=vec4(
        (x_ndc+1.0)*half_width,
        (1.0-y_ndc)*half_height,
        depth,valid);
}
