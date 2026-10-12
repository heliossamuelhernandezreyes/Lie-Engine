shader_type spatial;
// Lie 0.4: GPU Z-buffer geometry plus deterministic coverage blending.
// Both views are opaque depth-writing meshes. One or the other survives
// for each screen pixel via a 4x4 Bayer mask; NO alpha transparency sorting.
// Geometry disocclusions still produce gaps; this is not novel-view synthesis.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D lie_albedo : source_color, filter_nearest;
uniform sampler2D lie_normal : filter_nearest;
uniform vec3 light_direction_local = vec3(0.3, 0.2, 1.0);
uniform vec3 light_rgb : source_color = vec3(1.0, 0.88, 0.70);
uniform vec3 node_tint : source_color = vec3(1.0);
uniform float light_intensity : hint_range(0.0, 4.0) = 0.8;
uniform float ambient_level : hint_range(0.0, 1.0) = 0.32;
uniform float view_blend : hint_range(0.0, 1.0) = 0.0;
uniform bool second_pass = false;

float bayer_threshold(vec2 pixel) {
    int x = int(mod(floor(pixel.x), 4.0));
    int y = int(mod(floor(pixel.y), 4.0));
    const int mask[16] = {0, 8, 2, 10, 12, 4, 14, 6,
                          3, 11, 1, 9, 15, 7, 13, 5};
    return (float(mask[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
    float threshold = bayer_threshold(FRAGCOORD.xy);
    if (second_pass && threshold >= view_blend) {
        discard;
    }
    if (!second_pass && threshold < view_blend) {
        discard;
    }
    vec4 base = texture(lie_albedo, UV);
    if (base.a < 0.5) {
        discard;
    }
    vec3 n_b = texture(lie_normal, UV).rgb * 2.0 - 1.0;
    vec3 n_local = normalize(vec3(n_b.x, n_b.z, -n_b.y));
    float diffuse = max(dot(n_local, normalize(light_direction_local)), 0.0);
    ALBEDO = base.rgb * node_tint * (vec3(ambient_level) +
        diffuse * light_intensity * light_rgb);
}
