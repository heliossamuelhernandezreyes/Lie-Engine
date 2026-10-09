shader_type spatial;
// LIE-03: fragments are rasterized from depth-reconstructed 3D triangles.
// Their REAL 3D positions participate in the GPU's regular Z-buffer.
// It is sampled/discretized depth geometry, NOT perfect per-pixel reconstruction.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D lie_albedo : source_color, filter_nearest;
uniform sampler2D lie_normal : filter_nearest;
uniform vec3 light_direction_local = vec3(0.3, 0.2, 1.0);
uniform vec3 light_rgb : source_color = vec3(1.0, 0.88, 0.70);
uniform vec3 node_tint : source_color = vec3(1.0);
uniform float light_intensity : hint_range(0.0, 4.0) = 0.8;
uniform float ambient_level : hint_range(0.0, 1.0) = 0.32;

void fragment() {
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
