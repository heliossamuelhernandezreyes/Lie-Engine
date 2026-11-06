"""Validate calibrated numeric views, not their decorative PNG previews."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from lie_asset_contract import inspect_bank,proper_rotation
def verify(root):
    catalog=json.loads((root/'catalog.json').read_text());contract=inspect_bank((root/'library.bin').read_bytes(),catalog)
    profile=json.loads((root/'asset-profile.json').read_text());proper_rotation(profile['source_to_lie'])
    manifest=json.loads((root/'views.json').read_text());rows=[];triangle_ids=set()
    for view in manifest['views']:
        p=root/view['file'];assert hashlib.sha256(p.read_bytes()).hexdigest()==view['sha256']
        a=np.load(p);mask=a['mask'];positions=a['position_m'];normals=a['normal_world'];rgb=a['color_linear'];assert int(mask.sum())==view['valid_pixels'] and mask.any()
        assert np.isfinite(positions[mask]).all() and np.isnan(positions[~mask]).all();assert np.isinf(a['depth_m'][~mask]).all()
        assert np.isfinite(rgb).all() and ((rgb>=0)&(rgb<=1)).all();assert np.max(abs(np.linalg.norm(normals[mask],axis=1)-1))<1e-4
        assert (a['triangle_id'][mask]<500000).all();triangle_ids.update(a['triangle_id'][mask].tolist())
        pose=np.array(view['world_from_camera']);proper_rotation(pose[:3,:3]);h,w=mask.shape;rows_px,cols=np.mgrid[:h,:w]
        origins=pose[:3,3]+((cols+.5)/w-.5)[...,None]*view['span_m']*pose[:3,0]+(.5-(rows_px+.5)/h)[...,None]*view['span_m']*pose[:3,1]
        reconstructed=origins[mask]+a['depth_m'][mask,None]*np.array(view['forward_world'])
        error=float(np.max(np.linalg.norm(reconstructed-positions[mask],axis=1)));assert error<1e-6
        rows.append(dict(file=view['file'],valid_pixels=int(mask.sum()),position_reprojection_max_m=error))
    assert len(rows)==38
    report=dict(schema='lie-scanned-brick-verification/1',bank_sha256=contract['bank_sha256'],views=len(rows),original_triangles=500000,observed_original_triangles=len(triangle_ids),
                source_samples=catalog['sample_count'],native_mesh_required=False,rows=rows,material_limit='original vertex color, source roughness factor; acquisition lighting/delighting not certified')
    (root/'view-verification.json').write_text(json.dumps(report,indent=2)+'\n');print('CALIBRATED SCAN VERIFIED',len(rows),'views;',len(triangle_ids),'observed source triangles')
    return report
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--capture',type=Path,required=True);a=p.parse_args();verify(a.capture)
