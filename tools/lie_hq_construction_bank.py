"""Compile immutable source banks plus a virtual catalog for cross-bank sets."""
import argparse,copy,json,hashlib,shutil
from pathlib import Path
import numpy as np
from lie_asset_capture import capture
from lie_asset_contract import inspect_bank
from lie_optical_normals import inspect_optical
from lie_hq_construction_sources import write
from lie_asset_sets import compile_set
COUNTS=(120000,24000,6000)
def group(name,spec):return 'door' if name=='wood_door_leaf' else spec['material']
def virtual_catalog(catalogs):
    identity={name:{'sha256':c['sha256'],'optical':c.get('optical_normal_sidecar',{}).get('sha256')} for name,c in catalogs.items()}
    sha=hashlib.sha256(json.dumps(identity,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return {'sha256':sha,'masters':{bank+'/'+name:desc for bank,c in catalogs.items() for name,desc in c['masters'].items()}},identity
def compile_scene(document,name,catalogs):
    virtual,identity=virtual_catalog(catalogs)
    result=compile_set(document,name,virtual)
    for row in result:
        bank,master=row['master'].split('/',1);row.update(bank=bank,master=master)
    return {'schema':'lie-cross-bank-scene/1','scene_identity':virtual['sha256'],'bank_bindings':identity,'set':name,'instances':result}
def build(base,sources,output):
    output.mkdir(parents=True,exist_ok=True);bank_root=output/'banks';bank_root.mkdir(exist_ok=True)
    target=bank_root/'brick';target.mkdir(exist_ok=True)
    for filename in ('library.bin','catalog.json','asset-contract.json','provenance.json','asset-profile.json'):shutil.copy2(base/filename,target/filename)
    catalogs={'brick':json.loads((target/'catalog.json').read_text())};specs=json.loads((sources/'manifest.json').read_text());groups={}
    for name,entry in specs.items():groups.setdefault(group(name,entry['spec']),[]).append(name)
    for bank,names in groups.items():
        raw=bytearray();optical=bytearray();masters={};triangles=0
        for name in names:
            source=sources/specs[name]['source'];root=source.parent;part=output/'individual'/name
            counts=(480000,64000,16000) if bank=='door' else COUNTS
            cat=capture(source,root/(name+'-provenance.json'),part,counts=counts,asset_profile=json.loads((root/(name+'-profile.json')).read_text()))
            desc=copy.deepcopy(cat['masters'][name]);offset=len(raw)//80
            for level in desc['levels']:level['start']+=offset
            info=specs[name];low=np.array(info['bounds_min']);high=np.array(info['bounds_max'])
            desc.update(bounds_size=(high-low).tolist(),bounds_center=((high+low)/2).tolist(),scale_policy='authored_positive',source_geometry=info,source_provenance=json.loads((root/(name+'-provenance.json')).read_text()),anchors={'center':[0,0,0],'left':[float(low[0]),0,0],'right':[float(high[0]),0,0],'top':[0,float(high[1]),0],'bottom':[0,float(low[1]),0]})
            raw.extend((part/'library.bin').read_bytes());optical.extend((part/'optical-normals.bin').read_bytes());masters[name]=desc;triangles+=info['triangles']
        if len(raw)>64*1024*1024:raise ValueError('bank_core_budget')
        sha=hashlib.sha256(raw).hexdigest();cat={'schema':1,'stride':80,'bytes':len(raw),'sample_count':len(raw)//80,'sha256':sha,'masters':masters,'source_original_triangles':triangles,'source_mesh_drawn':False,'source_kind':'authored geometry with original photographic PBR','credit':'Powered by Poly Haven','optical_normal_sidecar':inspect_optical(optical,sha,len(raw)//80)}
        dst=bank_root/bank;dst.mkdir(exist_ok=True);(dst/'library.bin').write_bytes(raw);(dst/'optical-normals.bin').write_bytes(optical);write(dst/'catalog.json',cat);write(dst/'asset-contract.json',inspect_bank(raw,cat));catalogs[bank]=cat
        print('SCENE BANK',bank,len(raw),len(optical),sha,flush=True)
    virtual,identity=virtual_catalog(catalogs);assets={}
    for bank,c in catalogs.items():
        for name in c['masters']:
            if bank=='brick' and name not in ('scanned_brick','half_left','half_right'):continue
            assets[bank+'/'+name]={'master':bank+'/'+name,'role':'scanned_brick' if bank=='brick' else 'photographic_'+bank,'scale_policy':'rigid' if bank=='brick' else 'authored_positive'}
    document={'schema':'lie-asset-sets/1','bank_sha256':virtual['sha256'],'assets':assets,'sets':{}}
    manifest={'schema':'lie-hq-construction/1','banks':list(catalogs),'bank_bindings':identity,'scene_identity':virtual['sha256'],'assets':list(assets),'original_brick_bank_unchanged':True,'optical_normals_separate_from_geometry':True,'physical_android_tested':False}
    write(output/'manifest.json',manifest);write(output/'sets.json',document)
    return catalogs,document
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();build(a.base,a.sources,a.output)
