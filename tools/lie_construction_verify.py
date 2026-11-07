"""Independent integrity, source closure, opening and budget checks for this kit."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank
from lie_asset_sets import compile_set
from lie_construction_sources import SPECS
from lie_gltf_vertex_color import load_colored_glb
def verify(base,bank,sources):
    raw=(bank/'library.bin').read_bytes();previous=(base/'library.bin').read_bytes();assert raw[:len(previous)]==previous
    catalog=json.loads((bank/'catalog.json').read_text());inspect_bank(raw,catalog);defs=json.loads((bank/'asset-sets.json').read_text());assert len(catalog['masters'])==13
    for name in SPECS:
        p=sources/(name+'.glb');master=catalog['masters'][name];assert hashlib.sha256(p.read_bytes()).hexdigest()==master['source_provenance']['expected_sha256'];mesh=load_colored_glb(p)[0];assert mesh.is_watertight and mesh.is_winding_consistent and mesh.volume>0
    scenes={}
    for mode in ('wall','house'):
        for seed in (2102,7319):
            r=json.loads((bank/f'{mode}-{seed}.json').read_text());assert r['bank_sha256']==catalog['sha256'];assert len(r['instances'])<=8192
            kinds={e.get('joint_kind') for e in r['instances']};assert {'bed','head'}<=kinds
            for e in r['instances']:
                if 'joint_kind' not in e:continue
                a,b=e['interval_half_cells']
                for h in r['openings']:
                    if h['section']!=e['section']:continue
                    for row in e['touch_rows']:
                        if h['row']<=row<h['row']+h['rows']:
                            if a==b:assert a<=h['column']*2 or a>=(h['column']+h['columns'])*2
                            else:assert b<=h['column']*2 or a>=(h['column']+h['columns'])*2
            scenes[f'{mode}-{seed}']=dict(instances=len(r['instances']),beds=sum(e.get('joint_kind')=='bed' for e in r['instances']),heads=sum(e.get('joint_kind')=='head' for e in r['instances']))
    for name in defs['sets']:compile_set(defs,name,catalog)
    proof=dict(schema='lie-construction-kit-verification/1',bank_sha256=catalog['sha256'],bytes=len(raw),masters=13,new_sources_verified=8,source_prefix_unchanged=True,sets_checked=len(defs['sets']),scenes=scenes)
    (bank/'construction-verification.json').write_text(json.dumps(proof,indent=2)+'\n');print('KIT VERIFIED',proof);return proof
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--bank',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);a=p.parse_args();verify(a.base,a.bank,a.sources)
