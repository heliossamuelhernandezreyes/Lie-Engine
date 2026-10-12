"""Same-pose renderer ablation against independent Blender/Cycles images.

The baseline is actually executed in the same job. Reference lighting,
camera, pose, source textures and tone mapping remain fixed.
"""
import json
from pathlib import Path
import statistics
import sys
from PIL import Image, ImageChops, ImageDraw, ImageStat


def measure(actual, reference, mask, color_mask):
    actual=Image.open(actual).convert('RGBA')
    reference=Image.open(reference).convert('RGBA')
    mask=Image.open(mask).convert('RGBA')
    a=actual.getchannel('A').point(lambda x:255 if x>=128 else 0)
    b=mask.getchannel('A').point(lambda x:255 if x>=128 else 0)
    intersection=ImageChops.darker(a,b);union=ImageChops.lighter(a,b)
    iou=sum(intersection.histogram()[128:])/max(sum(union.histogram()[128:]),1)
    error=ImageStat.Stat(ImageChops.difference(actual.convert('RGB'),reference.convert('RGB')),color_mask)
    return {'silhouette_iou':iou,'foreground_rgb_mae':sum(error.mean)/3/255}


def compare(root):
    diagnostic=json.loads((root/'lie21-diagnostic.json').read_text())
    baseline=json.loads((root/'lie20-baseline/lie20-diagnostic.json').read_text())
    assert not diagnostic['failed'] and not baseline['failed']
    assert diagnostic['visible_source_meshes']==0 and diagnostic['asset_uploads']==1
    assert diagnostic['device']==baseline['device']
    cases=[]
    for case in diagnostic['cases']:
        name=case['name'];reference=root/f'captures/human_quality/reference-{name}-beauty.png';mask=root/f'captures/human_quality/reference-{name}-mask.png'
        paths=[root/f'lie20-baseline/lie20-{name}.png',root/f'lie21-{name}.png',mask]
        masks=[Image.open(p).convert('RGBA').getchannel('A').point(lambda x:255 if x>=128 else 0) for p in paths]
        common=ImageChops.darker(ImageChops.darker(masks[0],masks[1]),masks[2])
        old=measure(paths[0],reference,mask,common)
        new=measure(paths[1],reference,mask,common)
        cases.append({'name':name,'baseline':old,'quality':new,'matched_camera_and_authored_pose':True})
    old_mae=statistics.mean(c['baseline']['foreground_rgb_mae'] for c in cases)
    new_mae=statistics.mean(c['quality']['foreground_rgb_mae'] for c in cases)
    old_iou=statistics.mean(c['baseline']['silhouette_iou'] for c in cases)
    new_iou=statistics.mean(c['quality']['silhouette_iou'] for c in cases)
    min_iou=min(c['quality']['silhouette_iou'] for c in cases)
    gates={'every_silhouette_at_least_098':min_iou>=.98,
           'mean_silhouette_improves_at_least_0007':new_iou-old_iou>=.007,
           'mean_rgb_error_reduces_at_least_5_percent':new_mae<=old_mae*.95}
    profiles=[p['gpu_ns']/1e6 for p in diagnostic['profile'] if p['gpu_ns']>0]
    old_profiles=[p['gpu_ns']/1e6 for p in baseline['profile'] if p['gpu_ns']>0]
    result={'cases':cases,'gates':gates,'gate_passed':all(gates.values()),
            'baseline_mean_rgb_mae':old_mae,'quality_mean_rgb_mae':new_mae,'rgb_error_reduction':1-new_mae/old_mae,
            'baseline_mean_silhouette_iou':old_iou,'quality_mean_silhouette_iou':new_iou,'minimum_silhouette_iou':min_iou,
            'baseline_gpu_pass_median_ms':statistics.median(old_profiles) if old_profiles else None,
            'quality_gpu_pass_median_ms':statistics.median(profiles) if profiles else None,
            'baseline_allocation_bytes':baseline['allocation_bytes'],'quality_allocation_bytes':diagnostic['allocation_bytes'],
            'output_size':diagnostic['output_size'],'internal_size':diagnostic['internal_size'],
            'samples':diagnostic['master']['sample_count'],'capture_resolution':diagnostic['master']['capture_resolution'],
            'device':diagnostic['device'],'timing_scope':diagnostic['timing_scope'],
            'color_limit':'Cycles still uses different volumetric scattering and indirect transport. RGB error is a fixed experimental comparison, not physical equivalence.',
            'hyperrealism_achieved':False}
    (root/'lie21-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    rows=['neutral','turned','profile'];sheet=Image.new('RGB',(1536,512*len(rows)+100),(15,22,33));draw=ImageDraw.Draw(sheet)
    draw.text((22,16),'LIE-21 | Actual GPU reconstruction, fixed cameras and poses',fill=(91,220,244))
    draw.text((22,42),'LIE-20 baseline',fill='white');draw.text((534,42),'LIE-21 weighted + supersampled',fill='white');draw.text((1046,42),'Native Blender + Cycles',fill='white')
    draw.text((22,65),'Same master and reference settings | Lee Perry-Smith / Infinite-Realities | CC BY 3.0',fill=(177,191,207))
    for row,name in enumerate(rows):
        for col,path in enumerate([root/f'lie20-baseline/lie20-{name}.png',root/f'lie21-{name}.png',root/f'captures/human_quality/reference-{name}-beauty.png']):
            image=Image.open(path).convert('RGBA');background=Image.new('RGBA',image.size,(15,22,33,255));background.alpha_composite(image)
            sheet.paste(background.convert('RGB'),(col*512,100+row*512))
        draw.text((12,106+row*512),name,fill=(91,220,244))
    sheet.save(root/'lie21-comparison.png')
    print('LIE21 QUALITY COMPARISON',json.dumps(result,indent=2))
    if not result['gate_passed']:raise SystemExit('LIE21 fixed quality gates failed')
    return result


if __name__=='__main__':compare(Path(sys.argv[1]).resolve())
