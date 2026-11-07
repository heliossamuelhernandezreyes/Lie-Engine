"""SHA-locked, byte-exact LOD ranges in existing immutable capture files.

No resampling, quantization, changed records or duplicated page payloads.
"""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank
from lie_optical_normals import inspect_optical

def build(root):
    manifest=json.loads((root/'manifest.json').read_text());result={}
    for name in manifest['banks']:
        path=root/'banks'/name;catalog=json.loads((path/'catalog.json').read_text());raw=(path/'library.bin').read_bytes();inspect_bank(raw,catalog);optical=catalog.get('optical_normal_sidecar',{});normal=(path/optical['file']).read_bytes() if optical else b''
        if optical:assert inspect_optical(normal,catalog['sha256'],catalog['sample_count'])==optical
        entries={}
        for master,desc in catalog['masters'].items():
            # Preserve the accepted Godot Vector3 float32 low + size sequence.
            # Recomputing high independently in float64 moves a few edge hits.
            low=np.array([c-s/2 for c,s in zip(desc.get('bounds_center',[0,0,0]),desc['bounds_size'])],dtype='<f4');high=low+np.array(desc['bounds_size'],dtype='<f4');low=low.astype(float).tolist();high=high.astype(float).tolist()
            if 'modifications' in desc:
                m=desc['modifications'];low=m['bounds_min'].copy();high=m['bounds_max'].copy();pivot=(low[0]+high[0])/2;low[0]-=pivot;high[0]-=pivot
            for lod,level in enumerate(desc['levels']):
                start,count=level['start'],level['count'];key=f'{start}:{count}'
                if key in entries:raise ValueError('ambiguous_source_range')
                entries[key]=dict(master=master,lod=lod,start=start,count=count,core_sha256=hashlib.sha256(raw[start*80:(start+count)*80]).hexdigest(),optical_sha256=hashlib.sha256(normal[start*16:(start+count)*16]).hexdigest() if optical else None,low=low,high=high)
        doc=dict(schema='lie-capture-page-index/1',bank_sha256=catalog['sha256'],optical_sha256=optical.get('sha256'),core_bytes=len(raw),optical_bytes=len(normal),entries=entries,policy='exact existing LOD records; no source changes')
        (path/'pages.json').write_text(json.dumps(doc,indent=2)+'\n');result[name]=dict(pages=len(entries),core_bytes=len(raw),optical_bytes=len(normal))
    print(json.dumps(result));return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();build(a.root)
