"""Compile the existing wall's explicit ownership into the common field ABI."""
import hashlib,json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]

def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text());model=json.loads((root/'light-model.json').read_text())
    n=len(model['patches']);owners=np.full(n,0xffffffff,dtype='<u4')
    poses=cat['wall05']['poses'];boxes=model['direct_shadow_boxes']
    if len(poses)!=len(boxes):raise ValueError('wall owner/box count')
    for index,pose in enumerate(poses):
        first=int(pose['node_start'])
        if first<0 or first+9>n or (owners[first:first+9]!=0xffffffff).any():raise ValueError('wall node ownership')
        owners[first:first+9]=index
    (root/'field-owners.bin').write_bytes(owners.tobytes())
    rows=np.array([[*low,0.,*high,0.] for low,high in boxes],dtype='<f4')
    (root/'field-boxes.bin').write_bytes(np.array([len(boxes),0,0,0],dtype='<u4').tobytes()+rows.tobytes())
    names={'factors':'indirect_sparse.bin','outgoing':'outgoing-csr.bin','optics':'optics.bin','planes':'shadow-caps.bin','owners':'field-owners.bin','boxes':'field-boxes.bin'}
    proof={'schema':'lie-light-field-sources/1','source_bank_sha256':cat['sha256'],'source_light_sha256':hashlib.sha256((root/'light-model.json').read_bytes()).hexdigest(),'units':'meters; relative linear RGB power','patches':n,'sources':{}}
    for key,name in names.items():
        raw=(root/name).read_bytes();proof['sources'][key]={'file':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    (root/'light-field.json').write_text(json.dumps(proof,indent=2)+'\n');return proof

if __name__=='__main__':print(json.dumps(prepare(),indent=2))
