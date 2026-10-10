"""Compare actual Lie frames with independent Blender camera/pose references."""
import json
from pathlib import Path
import statistics
import sys
from PIL import Image, ImageChops, ImageDraw, ImageStat


def compare(root):
    diagnostics=json.loads((root/'lie20-diagnostic.json').read_text())
    cases=[]
    for entry in diagnostics['cases']:
        name=entry['name']
        actual=Image.open(root/f'lie20-{name}.png').convert('RGBA')
        mask=Image.open(root/f'captures/human_master/reference-{name}-mask.png').convert('RGBA')
        reference=Image.open(root/f'captures/human_master/reference-{name}-beauty.png').convert('RGBA')
        a=actual.getchannel('A').point(lambda x:255 if x>=128 else 0)
        b=mask.getchannel('A').point(lambda x:255 if x>=128 else 0)
        intersection=ImageChops.darker(a,b);union=ImageChops.lighter(a,b)
        num=sum(intersection.histogram()[128:]);den=sum(union.histogram()[128:]);iou=num/max(den,1)
        error=ImageStat.Stat(ImageChops.difference(actual.convert('RGB'),reference.convert('RGB')),intersection)
        mae=sum(error.mean)/3/255
        cases.append({'name':name,'silhouette_iou':iou,'foreground_rgb_mae':mae,'matched_camera_and_authored_pose':True,
            'color_limit':'Cycles uses a different scattering, ambient transport and shadow model; RGB error is descriptive.'})
    source=root/'captures/human_master/master.json'
    master=json.loads(source.read_text())
    rows=['neutral','turned','profile'];sheet=Image.new('RGB',(1024,512*len(rows)+100),(15,22,33));draw=ImageDraw.Draw(sheet)
    draw.text((22,18),'LIE · Captured human / invisible deformation',fill=(91,220,244))
    draw.text((22,42),'Lie samples                                      Blender original + Cycles',fill='white')
    draw.text((22,65),'Same camera and pose · lighting models differ · Lee Perry-Smith / Infinite-Realities · CC BY 3.0',fill=(177,191,207))
    for row,name in enumerate(rows):
        for col,path in enumerate([root/f'lie20-{name}.png',root/f'captures/human_master/reference-{name}-beauty.png']):
            image=Image.open(path).convert('RGBA');background=Image.new('RGBA',image.size,(15,22,33,255));background.alpha_composite(image)
            sheet.paste(background.convert('RGB'),(col*512,100+row*512))
        draw.text((12,106+row*512),name,fill=(91,220,244))
    sheet.save(root/'lie20-comparison.png')
    profiles=[p['gpu_ns']/1e6 for p in diagnostics['profile'] if p['gpu_ns']>0]
    result={'cases':cases,'minimum_silhouette_iou':min(c['silhouette_iou'] for c in cases),
        'silhouette_gate':.96,'gate_passed':all(c['silhouette_iou']>=.96 for c in cases),
        'samples':master['sample_count'],'capture_views':len(master['capture_views']),'capture_resolution':master['capture_resolution'],
        'lie_gpu_pass_median_ms':statistics.median(profiles) if profiles else None,
        'timing_scope':diagnostics['timing_scope'],'max_native_blender_position_error_m':diagnostics['max_position_error_m'],
        'art_limits':master['limitations'],'hyperrealism_achieved':False}
    (root/'lie20-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    print('LIE20 IMAGE COMPARISON',json.dumps(result,indent=2))
    if not result['gate_passed']:
        raise SystemExit('Human silhouette gate failed: >= 0.96 required for every fixed camera/pose')
    return result


if __name__=='__main__':compare(Path(sys.argv[1]).resolve())
