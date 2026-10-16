"""Immutable spatial query permutations. Source identity and samples are unchanged."""
import hashlib,json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def sha(data):return hashlib.sha256(data).hexdigest()
def compile_order(samples,references,levels):
    a=np.asarray(samples,dtype='<f4');refs=np.asarray(references,dtype='<u4')
    if a.ndim!=2 or a.shape[1]!=20 or not np.isfinite(a).all() or len(refs)==0 or refs.max()>=len(a):raise ValueError('query order source contract')
    p=a[:,:3].astype(float);lo=p.min(0);span=np.maximum(p.max(0)-lo,1e-20)
    xyz=np.clip((p-lo)/span*1023,0,1023).astype(np.uint32);codes=np.zeros(len(p),dtype=np.uint32)
    for bit in range(10):
        for axis in range(3):codes|=((xyz[:,axis]>>bit)&1)<<(bit*3+axis)
    chunks=[];meta=[];offset=0;keys=set()
    for entries in levels:
        work=0;indices=[]
        for at,count,owner,base in entries:
            if min(at,owner,base)<0 or count<1 or at+count>len(refs) or base!=work:raise ValueError('query order job contract')
            local=np.arange(count,dtype=np.uint32)
            indices.append(base+local[np.lexsort((local,codes[refs[at:at+count]]))]);work+=count
        if work>750000 or entries[0][1] in keys:raise ValueError('query order capacity/key')
        keys.add(entries[0][1]);raw=np.concatenate(indices).astype('<u4').tobytes();chunks.append(raw)
        meta.append({'key':entries[0][1],'offset':offset,'work':work,'jobs_sha256':sha(np.asarray(entries,dtype='<u4').tobytes())});offset+=work
    data=b''.join(chunks)
    return data,{'schema':'lie-visibility-order/1','bytes':len(data),'sha256':sha(data),'levels':meta,'scope':'per-instance spatial Morton order of original projection IDs; exact permutation; camera/light independent; no geometry or visibility approximation'}
def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text());source=json.loads((root/'surface-source.json').read_text());raw=(root/'library.bin').read_bytes();refs=(root/'surface-refs.bin').read_bytes()
    if sha(raw)!=cat['sha256'] or sha(refs)!=source['packets']['references']['sha256']:raise ValueError('query order source identity')
    data,proof=compile_order(np.frombuffer(raw,dtype='<f4').reshape(-1,20),np.frombuffer(refs,dtype='<u4'),cat['wall05']['instance_jobs'])
    proof.update(file='visibility-order.bin',source_bank_sha256=sha(raw),source_references_sha256=sha(refs));(root/proof['file']).write_bytes(data);(root/'visibility-order.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
if __name__=='__main__':print(json.dumps(prepare(),indent=2))
