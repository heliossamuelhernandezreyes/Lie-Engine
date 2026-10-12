#[compute]
#version 450

// Lie 0.6 GPU stage: FOUR pre-reprojected candidates per target pixel.
// Depth precedence / confidence-aware crossfade is executed on compute GPU.
// Projection of source pixels is NOT performed by this kernel.
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;

layout(set=0,binding=0,std430) readonly buffer CandidateColor {
    vec4 colors[];
} candidate_color;
layout(set=0,binding=1,std430) readonly buffer CandidateProperties {
    // x=camera depth in meters; y=surface normal confidence [0,1];
    // z=angular confidence [0,1]; w=valid flag.
    vec4 params[];
} candidate_properties;
layout(set=0,binding=2,std430) buffer FusedOutput {
    // rgb=fused color, a=1 when any valid candidate contributed.
    vec4 pixels[];
} result;

const float DEPTH_TOLERANCE = 0.07;

void main() {
    uint pixel = gl_GlobalInvocationID.x;
    if (pixel >= uint(result.pixels.length())) {
        return;
    }
    uint first = pixel * 4u;
    float nearest = 1e30;
    for (uint view = 0u; view < 4u; view++) {
        vec4 p = candidate_properties.params[first + view];
        vec4 c = candidate_color.colors[first + view];
        if (p.w > 0.5 && c.a >= 0.5 && p.x > 0.0 && p.y > 0.0 && p.z > 0.0) {
            nearest = min(nearest, p.x);
        }
    }
    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;
    if (nearest < 1e29) {
        for (uint view = 0u; view < 4u; view++) {
            vec4 p = candidate_properties.params[first + view];
            vec4 c = candidate_color.colors[first + view];
            if (p.w < 0.5 || c.a < 0.5 || abs(p.x - nearest) > DEPTH_TOLERANCE) {
                continue;
            }
            float w = clamp(p.y, 0.0, 1.0) * clamp(p.z, 0.0, 1.0);
            color_sum += c.rgb * w;
            weight_sum += w;
        }
    }
    result.pixels[pixel] = weight_sum > 0.00001
        ? vec4(color_sum / weight_sum, 1.0) : vec4(0.0);
}
