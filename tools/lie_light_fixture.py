"""Real scan + existing concrete samples exercise the SAME shared GPU kernel."""
import json,zlib
from pathlib import Path
import numpy as np
from lie_light_interpolation import weights
from lie_wall02_bake import micro_patch_indices
ROOT=Path(__file__).resolve().parents[1]
def prepare():
    root=ROOT/'gpu_compute/captures/liewall06';cat=json.loads((root/'catalog.json').read_text());bank=np.fromfile(root/'library.bin',dtype='<f4').reshape(-1,20)
    model=json.loads((root/'light-model.json').read_text());patch=model['patches'][:9]
    p=[x['position'] for x in patch];n=[x['normal'] for x in patch];areas=[x['area'] for x in patch];g=[[0,9]]*9;points=[];ids=[];sources=[]
    source=bank[:220000];localid=micro_patch_indices(source);pose=cat['wall05']['poses'][0];c,s=np.cos(pose['yaw_rad']),np.sin(pose['yaw_rad']);R=np.array([[c,0,s],[0,1,0],[-s,0,c]])
    for i in np.linspace(0,len(source)-1,40,dtype=int):points.append(source[i,:3]@R.T+pose['center']);ids.append(int(localid[i]));sources.append('scanned_brick')
    parent=ROOT/'gpu_compute/assets/lie31';catalog=json.loads((parent/'catalog.json').read_text());a=np.frombuffer(zlib.decompress((parent/'hd_bank.zlib').read_bytes()),dtype='<f4').reshape(-1,20);level=catalog['masters']['concrete_panel']['levels'][0];a=a[level['start']:level['start']+level['count']];a=a[a[:,6]>.85]
    # Four finite patches on the genuine existing authored concrete sample face.
    tags=(a[:,0]>=0).astype(int)+2*(a[:,1]>=0).astype(int)
    for k in range(4):
        part=a[tags==k];p.append(part[:,:3].mean(0).tolist());normal=part[:,4:7].mean(0);normal/=np.linalg.norm(normal);n.append(normal.tolist());areas.append(.2);g.append([9,4])
    for i in np.linspace(0,len(a)-1,40,dtype=int):points.append(a[i,:3]);ids.append(9+int(tags[i]));sources.append('existing_authored_concrete_panel')
    # GPU inputs are float32; oracle starts from those identical source values.
    p=np.asarray(p,dtype='<f4').astype(float);n=np.asarray(n,dtype='<f4').astype(float);areas=np.asarray(areas,dtype='<f4').astype(float);points=np.asarray(points,dtype='<f4').astype(float)
    expected=[weights(point,node,p,n,g,areas=areas).tolist() for point,node in zip(points,ids)]
    result={'positions':p.tolist(),'normals':n.tolist(),'areas':areas.tolist(),'groups':g,'points':points.tolist(),'nodes':ids,'expected':expected,'sources':sources,'bank_sha256':[cat['sha256'],catalog['sha256']],'concrete_source':'authored LIE30/31 concrete samples, not a separately scanned concrete object'}
    fixture=ROOT/'gpu_compute/fixtures/asset-light-reference.json';fixture.parent.mkdir(exist_ok=True);fixture.write_text(json.dumps(result,indent=2)+'\n')
    shader='''#[compute]
#version 450
layout(local_size_x=64) in;
struct Node {vec4 position_area;vec4 normal_pad;uvec4 group;};
layout(set=0,binding=0,std430) readonly buffer Queries {vec4 entries[];} queries;
layout(set=0,binding=1,std430) readonly buffer Nodes {Node entries[];} nodes;
layout(set=0,binding=2,std430) buffer Result {float entries[];} result;
layout(push_constant,std430) uniform Parameters {ivec4 counts;} parameters;
uvec2 lie_group(uint node) {return nodes.entries[node].group.xy;}
vec3 lie_position(uint node) {return nodes.entries[node].position_area.xyz;}
vec3 lie_normal(uint node) {return nodes.entries[node].normal_pad.xyz;}
float lie_area(uint node) {return nodes.entries[node].position_area.w;}
'''+(ROOT/'gpu_compute/shaders/lib/lie_irradiance_stencil.glslinc').read_text()+'''
void main() {
 uint i=gl_GlobalInvocationID.x;if(i>=uint(parameters.counts.x))return;
 vec3 point=queries.entries[i].xyz;uint node=uint(queries.entries[i].w);uvec2 group=lie_group(node);
 float sum=lie_stencil_sum(point,node);
 for(uint k=0u;k<uint(parameters.counts.y);k++)result.entries[i*uint(parameters.counts.y)+k]=k>=group.x && k<group.x+group.y?lie_stencil_weight(point,node,k)/sum:0.;
}
'''
    (ROOT/'gpu_compute/shaders/lie_asset_stencil_test.glsl').write_text(shader)
    return result
if __name__=='__main__':print('Shared GPU fixture queries:',len(prepare()['points']))
