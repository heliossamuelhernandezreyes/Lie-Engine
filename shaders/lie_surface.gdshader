shader_type spatial;
// Proof of concept: directional diffuse lighting applied to indexed surface data.
// Depth controls a bounded UV parallax offset; it does NOT write per-pixel depth.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D lie_albedo : source_color, filter_linear;
uniform sampler2D lie_normal : filter_linear;
uniform sampler2D lie_depth : filter_linear;
uniform vec3 light_direction_local = vec3(0.0, 0.0, 1.0);
uniform vec3 light_rgb : source_color = vec3(1.0, 0.85, 0.7);
uniform float light_intensity : hint_range(0.0, 4.0) = 0.8;
uniform float ambient_level : hint_range(0.0, 1.0) = 0.30;
uniform vec2 view_delta = vec2(0.0);
uniform float parallax_strength : hint_range(0.0, 0.15) = 0.065;

void fragment() {
    // Depth PNG: 0=near, 1=far, stored from the source capture camera.
    float encoded_depth = texture(lie_depth, UV).r;
    vec2 shift_uv = clamp(view_delta, vec2(-1.0), vec2(1.0))
        * (1.0 - encoded_depth) * parallax_strength;
    vec2 sample_uv = clamp(UV + shift_uv, vec2(0.001), vec2(0.999));
    vec4 base = texture(lie_albedo, sample_uv);
    if (base.a < 0.5) {
        discard;
    }
    // Capture normal channels are Blender Z-up world space. Convert to
    // Lie/Godot +Y up and +Z front: (x, y, z) <- (x, z, -y).
    vec3 n_blender = texture(lie_normal, sample_uv).rgb * 2.0 - 1.0;
    vec3 n_local = normalize(vec3(n_blender.x, n_blender.z, -n_blender.y));
    float diffuse = max(dot(n_local, normalize(light_direction_local)), 0.0);
    ALBEDO = base.rgb * (vec3(ambient_level) + light_rgb * diffuse * light_intensity);
}
