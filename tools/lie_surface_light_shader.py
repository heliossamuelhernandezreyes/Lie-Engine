"""Publish direct irradiance separately, without changing the accepted field."""
from pathlib import Path
from lie_light_field_shader import generate as field
from lie_wall05_shader import replace
ROOT=Path(__file__).resolve().parents[1]
def generate():
    s=field()
    s=replace(s,'void main() {','''layout(set=0,binding=25,std430) buffer SurfaceLights {
    uvec4 header; vec4 values[];
} surface_lights;
void main() {
    if(phase.data.x==6) {
        uint id=gl_GlobalInvocationID.x,n=uint(cfg.dims.x),L=uint(cfg.dims.y);
        if(id==0u)surface_lights.header=uvec4(n,L,16,1);
        if(id<L) {
            surface_lights.values[id*2u]=lights.values[id].position_radius;
            surface_lights.values[id*2u+1u]=vec4(lights.values[id].power.rgb/caps.values[id],cfg.tuning.x);
        }
        if(id<n*L) {
            uint node=id%n,l=id/n;
            vec3 E=lights.values[l].power.rgb*(weights.values[id]/caps.values[l])*
                transmittance(patches.values[node].center_area.xyz,lights.values[l].position_radius.xyz)/
                max(patches.values[node].center_area.w,1e-8);
            surface_lights.values[16u+id]=vec4(E,1);
        }
        return;
    }''')
    return s
if __name__=='__main__':(ROOT/'gpu_compute/shaders/lie_surface_light.glsl').write_text(generate())
