"""Wall adapter for a common source-scoped lighting group contract."""
import hashlib,json
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank
ROOT=Path(__file__).resolve().parents[1]
def compile_groups(groups,count):
    entries=np.full((count,4),0xffffffff,dtype='<u4');covered=np.zeros(count,dtype=bool)
    for base,size in groups:
        if type(base) is not int or type(size) is not int or size<1 or size>9 or base<0 or base+size>count or covered[base:base+size].any():raise ValueError('light_group_partition')
        entries[base:base+size]=[base,size,0,0];covered[base:base+size]=True
    if not covered.all():raise ValueError('light_group_partition')
    return np.array([1,count,9,1],dtype='<u4').tobytes()+entries.tobytes()
def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text());raw=(root/'library.bin').read_bytes();contract=inspect_bank(raw,cat)
    data=compile_groups([(i*9,9) for i in range(96)]+[(864,8)],872)
    proof={'schema':'lie-node-surface-groups/1','source_bank_sha256':cat['sha256'],'source_light_sha256':cat['lighting']['sha256'],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'groups':'same brick owner/material; mortar one continuous source instance; normal gate prevents face crossings','max_group_nodes':9,'algorithm':'convex normal-coherent inverse tangent-distance; area-scaled floor','runtime_semantics':'reconstruction of existing solved irradiance, no added light'}
    (root/'asset-contract.json').write_text(json.dumps(contract,indent=2)+'\n');(root/'light-groups.bin').write_bytes(data);(root/'light-groups.json').write_text(json.dumps(proof,indent=2)+'\n')
    return proof
if __name__=='__main__':print(json.dumps(prepare(),indent=2))
