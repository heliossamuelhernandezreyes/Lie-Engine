"""Matched-camera surface reconstruction checks, independent of lighting."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image, ImageFilter


def compare(root):
    root=Path(root);capture=root/'captures/face23'
    results=[]
    for name in ['open','half-blink','closed']:
        native=np.asarray(Image.open(capture/f'native-{name}-albedo.png').convert('RGBA'),dtype=float)/255
        lie=np.asarray(Image.open(root/f'lie23-{name}-albedo.png').convert('RGBA'),dtype=float)/255
        reference=np.asarray(Image.open(capture/f'native-{name}-mask.png').convert('RGBA'))[:,:,3]>=128
        coverage=lie[:,:,3]>=.5
        intersection=reference&coverage;union=reference|coverage
        iou=float(intersection.sum()/union.sum())
        ocular=Image.open(capture/f'native-{name}-eye-owner.png').convert('RGB').getchannel('R')
        ocular=np.asarray(ocular.filter(ImageFilter.MaxFilter(9)))>8
        interior=np.asarray(Image.fromarray((intersection*255).astype('uint8')).filter(ImageFilter.MinFilter(5)))>0
        skin=interior&~ocular
        error=np.abs(native[:,:,:3]-lie[:,:,:3])
        mae=float(error[skin].mean());p95=float(np.quantile(error[skin].mean(1),.95))
        results.append({'pose':name,'silhouette_iou':iou,'skin_rgb_mae':mae,'skin_pixel_error_p95':p95,'skin_pixels':int(skin.sum())})
    report={'camera_matched':True,'lighting_excluded':True,'ocular_materials_excluded':True,'cases':results,
            'limits':{'min_silhouette_iou':.985,'max_skin_rgb_mae':.03}}
    (root/'lie23-native-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LIE23 NATIVE IMAGE',json.dumps(report))
    assert all(r['silhouette_iou']>=.985 and r['skin_rgb_mae']<=.03 for r in results),results


if __name__=='__main__':
    compare(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'gpu_compute')
