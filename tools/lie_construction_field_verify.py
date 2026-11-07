"""Independent float64 field check and byte-level frozen-v5 image acceptance."""
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from lie_field_quality import solve

def verify_field(stage,fields,out):
    model=json.loads((stage/'construction-field-model.json').read_text());root=fields/'corner-2102';packets={key:(root/(key+'.bin')).read_bytes() for key in ['factors','outgoing','optics','owners','planes','boxes']};reference=solve(model,packets);actual=np.fromfile(stage/'construction-field-flux.f32',dtype='<f4').reshape(-1,4)[:,:3];truth=np.array(reference['flux']);delta=abs(actual-truth)
    report={'schema':'lie-construction-field-reference/1','nodes':len(actual),'edges':int(np.frombuffer(packets['factors'],'<u4')[1]),'max_error':float(delta.max()),'mean_error':float(delta.mean()),'reference_generation_totals_rgb':reference['generation_totals_rgb'],'reference_channel_totals':reference['channel_totals_by_generation'],'actual_total_flux_rgb':actual.sum(0,dtype='float64').tolist(),'passed':bool(np.isfinite(actual).all() and (actual>=0).all() and delta.max()<.00003),'reference':'float64 independent scatter with vector segment-box injection; same explicit coarse surface contract','physical_android_tested':False}
    out.mkdir(parents=True,exist_ok=True);(out/'field-reference.json').write_text(json.dumps(report,indent=2)+'\n');print('FIELD REFERENCE',json.dumps(report),flush=True)
    if not report['passed']:raise SystemExit('Construction field differs from independent float64')
    return report

def verify_pages(baseline,stage,out):
    rows={};peak=0.
    for p in sorted(baseline.glob('quality_*-color.f32')):
        q=stage/p.name;a=p.read_bytes();b=q.read_bytes();color_equal=a==b;name=p.name.replace('-color.f32','-depth.f32');depth_equal=(baseline/name).read_bytes()==(stage/name).read_bytes();difference=float(np.max(abs(np.frombuffer(a,'<f4')-np.frombuffer(b,'<f4'))));peak=max(peak,difference);rows[p.stem]={'rgba_bit_exact':color_equal,'depth_bit_exact':depth_equal,'peak_rgba_difference':difference,'v5_rgba_sha256':hashlib.sha256(a).hexdigest(),'new_rgba_sha256':hashlib.sha256(b).hexdigest()}
    result={'schema':'lie-construction-range-compatibility/1','views':len(rows),'peak_rgba_difference':peak,'passed':len(rows)==24 and all(x['rgba_bit_exact'] and x['depth_bit_exact'] for x in rows.values()),'cases':rows,'scope':'same selected captures, settings, resolution, device and driver; field mode disabled; not a cross-GPU bit-identity promise'}
    out.mkdir(parents=True,exist_ok=True);(out/'v5-compatibility.json').write_text(json.dumps(result,indent=2)+'\n');print('V5 COMPATIBILITY',result['views'],result['passed'],peak,flush=True)
    if not result['passed']:raise SystemExit('Frozen v5 native image changed; preserve failed evidence')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--fields',type=Path);p.add_argument('--baseline',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.fields:verify_field(a.stage,a.fields,a.output)
    if a.baseline:verify_pages(a.baseline,a.stage,a.output)
