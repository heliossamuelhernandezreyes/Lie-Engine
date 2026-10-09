shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Gray reflectance is linear DATA, not an sRGB photograph with baked shading.
uniform sampler2D gray_map : filter_nearest;
uniform sampler2D light_codes : filter_nearest;
uniform int patch_index = 0;
uniform int patch_count = 1;
uniform vec3 material_filter = vec3(1.0);
uniform float absorption = 0.2;
uniform float exposure = 1.0;

void fragment() {
    vec4 gray=texture(gray_map,UV);
    if(gray.a<0.5) discard;
    vec2 code_uv=vec2((float(patch_index)+0.5)/float(patch_count),0.5);
    vec3 incident=textureLod(light_codes,code_uv,0.0).rgb;
    vec3 radiance=gray.r*material_filter*(1.0-absorption)*incident/3.14159265359;
    // A fixed display mapping; HDR linear power remains intact in the code texture.
    vec3 c=max(radiance*exposure,vec3(0.0));
    ALBEDO=c/(vec3(1.0)+c);
}
