"""Immutable 32-byte visibility view, preserving all original source IDs/bits."""
import json
from pathlib import Path
import numpy as np
from lie_asset_surface import require_bank, sha
ROOT=Path(__file__).resolve().parents[1]
def compact(raw):
    if not raw or len(raw)%80:raise ValueError('shadow bank ABI')
    require_bank(np.frombuffer(raw,dtype='<f4').reshape(-1,20))
    return np.frombuffer(raw,dtype=np.uint8).reshape(-1,80)[:,:32].copy().tobytes()
def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text());raw=(root/'library.bin').read_bytes()
    if sha(raw)!=cat['sha256'] or len(raw)!=cat['bytes']:raise ValueError('shadow bank identity')
    data=compact(raw);(root/'shadow-view.bin').write_bytes(data)
    proof={'schema':'lie-shadow-view/1','file':'shadow-view.bin','source_bank_sha256':sha(raw),'source_count':len(raw)//80,'original_stride':80,'stride':32,'bytes':len(data),'sha256':sha(data),'scope':'first 32 original bytes per source ID; position/radius and normal/gray; no quantization, reorder, geometry or material change'}
    (root/'shadow-view.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
def prepare_reference():
    from lie_persistent_reference import prepare as reference
    cases=reference()
    for case in cases:case['bank_hex']=compact(bytes.fromhex(case['bank_hex'])).hex()
    path=ROOT/'gpu_compute/fixtures/compact-shadow-reference.json';path.write_text(json.dumps({'schema':'lie-compact-shadow-reference/1','oracle':'unchanged float64 exhaustive original 80-byte disk oracle','cases':cases},separators=(',',':'))+'\n');return path
if __name__=='__main__':print(json.dumps(prepare(),indent=2))
