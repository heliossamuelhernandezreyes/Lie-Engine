"""Page traversal tested against exhaustive float64 source intersections."""
import json
from pathlib import Path
import numpy as np
from lie_asset_surface import compile_blas,compile_scene,reference_rays
from lie_source_visibility_fixture import cases,pack_queries
from lie_spatial_pages import compile_pages
ROOT=Path(__file__).resolve().parents[1]
def prepare():
    result=cases()
    for case in result:
        bank=np.frombuffer(bytes.fromhex(case['bank_hex']),dtype='<f4').reshape(-1,20);_,_,roots=compile_blas(bank,[(0,len(bank))])
        pages,proof=compile_pages(bank,roots);case.update(pages_hex=pages.hex(),pages_proof=proof)
    def add(name,bank,ranges,instances,queries):
        nodes,leaves,roots=compile_blas(bank,ranges);scene=compile_scene(instances,roots);pages,proof=compile_pages(bank,roots)
        result.append(dict(name=name,bank_hex=bank.astype('<f4').tobytes().hex(),nodes_hex=nodes.hex(),leaves_hex=leaves.hex(),scene_hex=scene.hex(),pages_hex=pages.hex(),queries_hex=pack_queries(queries).hex(),expected=reference_rays(bank,instances,roots,queries),pages_proof=proof))
    rng=np.random.default_rng(572018)
    bank=np.zeros((192,20),dtype='<f4');bank[:,:3]=rng.uniform(-.015,.015,(len(bank),3));bank[:,3]=rng.uniform(.0007,.004,len(bank));bank[:,4:7]=rng.normal(size=(len(bank),3));bank[:,4:7]/=np.linalg.norm(bank[:,4:7],axis=1)[:,None]
    matrix=np.eye(4);matrix[:3,:3]=np.array([[.8,0,.2],[0,1.3,0],[-.2,0,.8]]);matrix[:3,3]=[.002,-.001,.003]
    queries=[]
    for i in range(256):
        p=rng.uniform(-.02,.02,3);n=rng.normal(size=3);n/=np.linalg.norm(n);light=p+n*.05
        if i<12:n=np.eye(3)[i%3]*(-1 if i%2 else 1);light=p+n*.05
        queries.append({'point':p.tolist(),'normal':n.tolist(),'light':light.tolist(),'reach':.025})
    add('random_two_roots_affine',bank,[(0,96),(96,96)],[{'root':0,'matrix':np.eye(4).tolist()},{'root':1,'matrix':matrix.tolist()}],queries)
    dense=np.zeros((512,20),dtype='<f4');dense[:,:3]=rng.uniform(-.00001,.00001,(512,3));dense[:,3]=.004;dense[:,6]=1
    add('dense_page_fallback',dense,[(0,512)],[{'root':0,'matrix':np.eye(4).tolist()}],[{'point':[0.,0.,-.003],'normal':[0.,0.,1.],'light':[0.,0.,1.]}])
    proof={'schema':'lie-spatial-pages-reference/1','oracle':'exhaustive float64 captured disks, independent of DDA and BLAS traversal','cases':result}
    (ROOT/'gpu_compute/fixtures/spatial-pages-reference.json').write_text(json.dumps(proof,separators=(',',':'))+'\n');return proof
if __name__=='__main__':print([(c['name'],len(c['expected'])) for c in prepare()['cases']])
