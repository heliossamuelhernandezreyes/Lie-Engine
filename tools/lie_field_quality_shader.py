"""Build quality transport from the accepted field; preserve its public ABI."""
from pathlib import Path
from lie_light_field_shader import generate as field
from lie_surface_light_shader import generate as surface
from lie_wall13_shader import generate_field as area
from lie_wall05_shader import replace
ROOT = Path(__file__).resolve().parents[1]


def generate():
    s = field()
    common = (ROOT/'gpu_compute/shaders/lib/lie_field_visibility.glslinc').read_text()+'\n'+(ROOT/'gpu_compute/shaders/lib/lie_field_quality.glslinc').read_text()
    s = replace(s, 'void main() {', common + '\nvoid main() {')
    s = replace(s, '    if(optical.config.x!=0u && optical.config.w!=0u && field_step(i))return;',
        '    if(optical.config.x!=0u && optical.config.w!=0u && quality.q.x>0u && lie_quality_step(i))return;\n'
        '    if(optical.config.x!=0u && optical.config.w!=0u && field_step(i))return;')
    s = replace(s, 'weights.values[i]=value;',
        'if(!lie_dynamic_clear(patches.values[p].center_area.xyz,lights.values[l].position_radius.xyz))value=0.;\n        weights.values[i]=value;')
    return s


def generate_surface():
    return surface(field_generator=generate)


def outputs():
    direct = (ROOT/'gpu_compute/shaders/lie_direct_light.glsl').read_text()
    for marker, name in [('STENCIL', 'lie_irradiance_stencil.glslinc'), ('BRDF', 'lie_opaque_brdf.glslinc')]:
        direct = direct.replace('// SHARED_'+marker, (ROOT/'gpu_compute/shaders/lib'/name).read_text())
    visibility = (ROOT/'gpu_compute/shaders/lib/lie_field_visibility.glslinc').read_text()
    direct = replace(direct, 'void main(){', visibility+'''
layout(set=0,binding=13,std430) readonly buffer FieldQuality {
    uvec4 q;vec4 parameters;vec4 data[];
} quality;
float lie_dynamic_visibility(uint light,vec3 p) {
    for(uint j=0u;j<quality.q.z;j++) {
        uint at=lights.header.x+j*2u;
        if(lie_segment_box(lights.v[light*2u].xyz,p,quality.data[at].xyz,quality.data[at+1u].xyz))return 0.;
    }
    return 1.;
}
void main(){''')
    direct = replace(direct, 'vec3 direction=lie_opaque_direction(lights.v[l*2u].xyz-hit.xyz);',
        '// Opaque fine visibility replaces the coarse occlusion gate. A zero\n'
        '        // node approximation must not erase an actually visible opening.\n'
        '        if(options.flags.w!=0u)gate=vec3(1);\n'
        '        vec3 direction=lie_opaque_direction(lights.v[l*2u].xyz-hit.xyz);')
    direct = replace(direct, '*gate*visibility(l,hit.xyz,n);', '*gate*visibility(l,hit.xyz,n)*lie_dynamic_visibility(l,hit.xyz);')
    return {'lie_field_quality.glsl': generate(),
            'lie_field_quality_area.glsl': area(field_generator=generate_surface),
            'lie_quality_direct_light.glsl': direct}


if __name__ == '__main__':
    for name, source in outputs().items():
        (ROOT/'gpu_compute/shaders'/name).write_text(source)
