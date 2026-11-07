"""Real-bank layout, source identity and rigid scan assembly audit."""
import argparse,json,hashlib,itertools
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank
from lie_optical_normals import inspect_optical

def audit(root,sources):
    manifest=json.loads((root/'manifest.json').read_text());catalogs={};reports={}
    for bank in manifest['banks']:
        p=root/'banks'/bank;c=json.loads((p/'catalog.json').read_text());raw=(p/'library.bin').read_bytes();inspect_bank(raw,c)
        if c.get('optical_normal_sidecar'):inspect_optical((p/'optical-normals.bin').read_bytes(),c['sha256'],c['sample_count'])
        catalogs[bank]=c;reports[bank]={'core_sha256':c['sha256'],'bytes':len(raw),'optical_bytes':c.get('optical_normal_sidecar',{}).get('bytes',0)}
    assert catalogs['brick']['sha256']=='dbdf7b21727d4ee9c789dd8cdedde29c42297deae359e5089315b1a744160916'
    source_manifest=json.loads((sources/'manifest.json').read_text());closed=0;verified={}
    for name,info in source_manifest.items():
        path=sources/info['source'];doc=json.loads(path.read_text());assert all(doc['closed_components']);closed+=len(doc['closed_components'])
        for spec in [doc['mesh'],*doc['maps'].values()]:
            file=(path.parent/spec['path']).resolve()
            if file not in verified:
                with file.open('rb') as f:verified[file]=hashlib.file_digest(f,'sha256').hexdigest()
            assert verified[file]==spec['sha256']
    rows={}
    for seed in [2102,7319]:
        scene=json.loads((root/('corner-'+str(seed)+'.json')).read_text());bricks=[e for e in scene['instances'] if e['bank']=='brick'];bounds=[];minimum=1.
        for e in bricks:
            R=np.asarray(e['basis_columns']).T;s=np.asarray(e['scale']);assert np.all(s==1) and np.allclose(R@R.T,np.eye(3),atol=1e-7) and abs(np.linalg.det(R)-1)<1e-7
            m=catalogs['brick']['masters'][e['master']];size=np.array(m['bounds_size']);center=np.array(m.get('bounds_center',[0,0,0]),float)
            if 'modifications' in m:
                low=np.array(m['modifications']['bounds_min']);high=np.array(m['modifications']['bounds_max']);size=high-low;center=(high+low)/2;center[0]=0
            half=np.abs(R)@size/2;p=np.asarray(e['origin'])+R@center;bounds.append((p-half,p+half))
        for i,(a,b) in enumerate(bounds):
            for c,d in bounds[i+1:]:
                overlap=np.minimum(b,d)-np.maximum(a,c);assert not np.all(overlap>1e-7),'overlapping scanned brick bounds'
                separated=-overlap[overlap<=0]
                if len(separated):minimum=min(minimum,float(separated.min()))
        rows[str(seed)]={'bricks':len(bricks),'rigid_proper_rotations':True,'conservative_brick_boxes_nonoverlapping':True,'minimum_axis_separation_m':minimum,'corner_gap_m':scene['corner_gap_m']}
    result={'schema':'lie-construction-data-audit/1','banks':reports,'source_masters':len(source_manifest),'closed_source_components':closed,'source_sha256_verified':True,'original_brick_bank_unchanged':True,'corners':rows,'scope':'scan box non-overlap only; intentional mortar/frame/foundation contacts are not globally nonintersecting','passed':True}
    (root/'data-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);a=p.parse_args();audit(a.root,a.sources)
