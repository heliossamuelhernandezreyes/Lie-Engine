shader_type spatial;
// Reprojected samples are already 3D triangles: standard GPU depth testing.
// Vertex colors are fused from two RGB captures by a CPU target-camera z-test.
// This is not a custom high-performance GPU reprojection implementation.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 scene_tint : source_color = vec3(1.0);

void fragment() {
    if (COLOR.a < 0.5) {
        discard;
    }
    ALBEDO = COLOR.rgb * scene_tint;
}
