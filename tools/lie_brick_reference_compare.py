"""Compare actual GPU readbacks with independently rendered Cycles radiance.

No exposure fitting, denoising, histogram matching or learned image metrics.
All error metrics use linear RGB. Preview-only mapping is fixed Reinhard/sRGB.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_erosion
from lie_brick_reference_math import metrics, preview


def raw(path, size):
    a = np.fromfile(path, dtype='<f4')
    if len(a) != size*size*4: raise ValueError('Unexpected GPU readback shape: '+str(path))
    a = a.reshape(size, size, 4)
    if not np.isfinite(a).all(): raise ValueError('Nonfinite GPU readback')
    return a


def compare(stage, output):
    fixture = stage/'captures/brick_reference'; manifest = json.loads((fixture/'manifest.json').read_text())
    native = json.loads((stage/'brick-reference-native.json').read_text())
    if native['failed'] or len(native['cases']) != len(manifest['cases']): raise ValueError('Native acceptance incomplete')
    output.mkdir(parents=True, exist_ok=True); size = manifest['resolution']; rows = {}; tiles = []
    for case in manifest['cases']:
        name = case['name']; refs = {}
        for channel, suffix in [('total','full'), ('direct','direct')]:
            a = np.load(fixture/(name+'-cycles-'+suffix+'.npy'))
            b = np.load(fixture/(name+'-cycles-'+('repeat' if suffix=='full' else 'direct-repeat')+'.npy'))
            refs[channel] = (a+b)*.5
            refs[channel+'_seed_difference'] = a[...,:3]-b[...,:3]
            refs[channel+'_noise_rmse_of_mean'] = float(.5*np.sqrt(np.mean((a[...,:3]-b[...,:3])**2)))
        refs['indirect'] = refs['total']-refs['direct']
        gbuffer = np.load(fixture/(name+'-source-gbuffer.npy')); owners = gbuffer[:,:,7].astype(int)
        reference_mask = refs['total'][:,:,3]>.99
        interior = binary_erosion(reference_mask, iterations=2)
        actual = {mode:raw(stage/(name+'-lie-'+mode+'.rgba32f'),size) for mode in ['total','direct','indirect','legacy','radius']}
        coverage = actual['total'][:,:,3]>.5
        row = {'coverage_iou': float((coverage&reference_mask).sum()/max((coverage|reference_mask).sum(),1)),
               'reference_pixels': int(reference_mask.sum()), 'reference_interior_pixels': int(interior.sum()),
               'missing_reference_interior_pixels': int((interior&~coverage).sum()),
               'reference_total_noise_rmse_of_mean': refs['total_noise_rmse_of_mean'],
               'reference_direct_noise_rmse_of_mean': refs['direct_noise_rmse_of_mean'],
               'reference_interior_seed_noise_proxy': {
                   'total_rmse_of_mean':float(.5*np.sqrt(np.mean(refs['total_seed_difference'][interior]**2))),
                   'indirect_rmse_of_mean':float(.5*np.sqrt(np.mean((refs['total_seed_difference'][interior]-refs['direct_seed_difference'][interior])**2))),
                   'scope':'Two independent seeds; an empirical noise proxy, not a certified confidence bound'},
               'linear': {mode:metrics(actual[mode][...,:3],refs[mode][...,:3],interior) for mode in ['total','direct','indirect']},
               'legacy_total': metrics(actual['legacy'][...,:3],refs['total'][...,:3],interior),
               'radius_total': metrics(actual['radius'][...,:3],refs['total'][...,:3],interior), 'regions': {}}
        for owner, instance in enumerate(case['instances']):
            selected = binary_erosion(owners==owner, iterations=2)&interior
            if selected.any():
                row['regions'][str(owner)+':'+instance['master']] = {
                    mode:metrics(actual[mode][...,:3], refs[mode][...,:3],selected) for mode in ['total','direct','indirect']}
        if name == 'calibration_plane':
            delta = np.array(case['light']['position'])-gbuffer[:,:,:3]; d2 = (delta*delta).sum(2)
            cosine = np.maximum(np.sum(gbuffer[:,:,3:6]*delta,2)/np.maximum(np.sqrt(d2),1e-20),0.)
            analytic = np.array(manifest['materials']['floor'])*case['light']['power']*cosine[:,:,None]/(4*math.pi**2*np.maximum(d2[:,:,None],1e-20))
            row['cycles_vs_analytic_lambert'] = metrics(refs['direct'][...,:3],analytic,interior)
            row['lie_vs_analytic_lambert'] = metrics(actual['direct'][...,:3],analytic,interior)
        rows[name] = row
        delta = abs(actual['total'][...,:3]-refs['total'][...,:3])
        # Identical display mapping and exposure for both radiance images.
        images = [preview(refs['total'][...,:3]), preview(actual['total'][...,:3]), preview(delta,8.)]
        tile = Image.new('RGB',(size*3,size+44),(17,22,29));draw = ImageDraw.Draw(tile)
        for col, (pixels, label) in enumerate(zip(images,['Cycles CPU','LIE: capturas + campo','Error absoluto x8'])):
            tile.paste(Image.fromarray(pixels),(col*size,26));draw.text((col*size+7,7),label,fill=(230,235,240))
        draw.text((7,size+29),name+' | L1 relativo: %.2f%% | IoU: %.4f'%(row['linear']['total']['relative_l1']*100,row['coverage_iou']),fill=(215,225,235));tiles.append(tile)
        Image.fromarray(images[0]).save(output/(name+'-cycles.png'));Image.fromarray(images[1]).save(output/(name+'-lie.png'))
    calibration = rows['calibration_plane']
    gates = {'cycles_analytic_relative_l1_below_1_percent':calibration['cycles_vs_analytic_lambert']['relative_l1']<.01,
             'lie_analytic_relative_l1_below_3_percent':calibration['lie_vs_analytic_lambert']['relative_l1']<.03,
             'calibration_coverage_iou_above_97_percent':calibration['coverage_iou']>.97,
             'aperture_direct_relative_l1_below_15_percent':rows['wall_opening']['linear']['direct']['relative_l1']<.15}
    report = {'schema':'lie-brick-independent-comparison/1','bank_sha256':manifest['bank_sha256'],
              'reference':manifest['reference'],'native':native,'cases':rows,'control_gates':gates,
              'control_gates_passed':all(gates.values()),'scene_fidelity_accepted':False,
              'scope':'Independent diagnostic, not a universal quality certification. Regional errors include finite graph/material/shadow/reconstruction approximations.',
              'image_mapping':{'exposure':1.,'tone_map':'Reinhard then sRGB, preview only','error_preview_gain':8.},
              'physical_android_tested':False,'source_manifest_sha256':hashlib.sha256((fixture/'manifest.json').read_bytes()).hexdigest(),
              'limitations':manifest['limits']}
    (output/'brick-reference-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
    sheet = Image.new('RGB',(size*3,sum(t.height for t in tiles)),(17,22,29));y=0
    for tile in tiles:sheet.paste(tile,(0,y));y+=tile.height
    sheet.save(output/'brick-reference-comparison.png')
    print(json.dumps({'control_gates':gates,'cases':{k:{'L1':v['linear']['total']['relative_l1'],'direct_L1':v['linear']['direct']['relative_l1'],'indirect_L1':v['linear']['indirect']['relative_l1'],'IoU':v['coverage_iou']} for k,v in rows.items()}},indent=2))
    if not all(gates.values()):raise ValueError('Predeclared calibration controls failed; preserve the diagnostic and investigate')
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--stage',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();compare(a.stage,a.output)
