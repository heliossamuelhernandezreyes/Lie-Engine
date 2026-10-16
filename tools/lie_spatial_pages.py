"""Immutable source-space cell -> CSR source-ID pages, shared by instances.

Cells contain conservative disk-sphere bounds. Exact disk tests still decide
visibility; no cell or invisible envelope becomes an opaque primitive.
"""
import json,math,struct
from pathlib import Path
import numpy as np
from lie_asset_surface import require_bank,sha
ROOT=Path(__file__).resolve().parents[1]
MAGIC=0x4c504731
MAX_AXIS=64

def compile_pages(samples,roots):
    a=require_bank(samples);bound=max(int(r['root']) for r in roots)+1
    if bound>1000000 or len({r['root'] for r in roots})!=len(roots):raise ValueError('page root domain')
    words=[MAGIC,1,len(roots),bound,8,8+bound,0,0]+[0]*bound+[0]*(16*len(roots));reports=[]
    for index,root in enumerate(roots):
        start,count=int(root['start']),int(root['count'])
        if not 0<=start<len(a) or not 1<=count<=len(a)-start:raise ValueError('page source range')
        source=a[start:start+count];p=source[:,:3].astype(float);r=source[:,3,None].astype(float)
        low=(p-r).min(0);high=(p+r).max(0);pad=2e-6*(1+np.maximum(abs(low),abs(high)))
        low=np.nextafter((low-pad).astype('<f4'),np.float32(-np.inf));high=np.nextafter((high+pad).astype('<f4'),np.float32(np.inf))
        longest=min(MAX_AXIS,max(1,math.ceil(math.sqrt(count/8))))
        dims=np.maximum(1,np.ceil((high.astype(float)-low)/(high.astype(float)-low).max()*longest)).astype(np.int32)
        width=((high-low)/dims.astype(np.float32)).astype(float)
        guard=4e-6*(1+abs(p))
        lower=np.clip(np.floor((p-r-guard-low)/width).astype(np.int32),0,dims-1)
        upper=np.clip(np.floor((p+r+guard-low)/width).astype(np.int32),0,dims-1)
        cells=[];ids=[];span=(upper-lower).max(0);source_ids=np.arange(start,start+count,dtype=np.uint32)
        for z in range(int(span[2])+1):
            for y in range(int(span[1])+1):
                for x in range(int(span[0])+1):
                    delta=np.array([x,y,z]);valid=np.all(lower+delta<=upper,axis=1);q=lower[valid]+delta
                    cells.append(((q[:,2]*dims[1]+q[:,1])*dims[0]+q[:,0]).astype(np.uint32));ids.append(source_ids[valid])
        cell=np.concatenate(cells);sid=np.concatenate(ids);order=np.lexsort((sid,cell));cell=cell[order];sid=sid[order]
        n=int(np.prod(dims));counts=np.bincount(cell,minlength=n);offsets=np.r_[0,np.cumsum(counts)].astype(np.uint32)
        offsets_at=len(words);words.extend(offsets.astype(int).tolist());ids_at=len(words);words.extend(sid.astype(int).tolist())
        at=8+bound+16*index;floats=lambda v:np.asarray(v,dtype='<f4').view('<u4').astype(int).tolist()
        desc=floats(low)+[int(dims[0])]+floats(high)+[int(dims[1])]+[int(dims[2]),offsets_at,ids_at,len(sid),n,start,count,int(root['root'])]
        words[at:at+16]=desc;words[8+int(root['root'])]=index+1
        reports.append({'root':int(root['root']),'start':start,'source_count':count,'dimensions':dims.astype(int).tolist(),'cells':n,'nonempty_cells':int(np.count_nonzero(counts)),'references':len(sid),'max_cell_references':int(counts.max()),'overloaded_cells_256':int(np.count_nonzero(counts>256))})
    words[6]=len(words);raw=np.asarray(words,dtype='<u4').tobytes()
    if len(raw)>32*1024*1024:raise ValueError('page packet exceeds 32 MiB budget')
    return raw,{'schema':'lie-spatial-pages/1','bytes':len(raw),'sha256':sha(raw),'roots':reports,'max_axis':MAX_AXIS,'layout':'8-word header, root-address table, 16-word descriptors, CSR offsets and original source IDs','scope':'immutable captured disk sphere bounds; instances share local pages; exact current-ray disk tests; overloaded/numerically unresolved rays fall back to BLAS'}

def prepare(root=ROOT/'gpu_compute/captures/liewall06'):
    root=Path(root);source=json.loads((root/'surface-source.json').read_text());raw=(root/'library.bin').read_bytes()
    if sha(raw)!=source['source_bank_sha256']:raise ValueError('page bank identity')
    data,proof=compile_pages(np.frombuffer(raw,dtype='<f4').reshape(-1,20),source['roots'])
    proof.update(file='spatial-pages.bin',source_bank_sha256=sha(raw),source_blas_sha256=source['packets']['nodes']['sha256'])
    (root/proof['file']).write_bytes(data);(root/'spatial-pages.json').write_text(json.dumps(proof,indent=2)+'\n');return proof
if __name__=='__main__':print(json.dumps(prepare(),indent=2))
