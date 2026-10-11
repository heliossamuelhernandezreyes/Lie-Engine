"""Matched silhouette and unlit skin comparisons for all module/view cases."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, binary_erosion


def compare(project):
    project=Path(project);root=project/'captures/face24'
    cases=json.loads((root/'native-oracle.json').read_text())['cases'];results=[]
    for case in cases:
        if not case['render']:continue
        code=case['code'];a=np.asarray(Image.open(project/f'lie24-{code}-albedo.png').convert('RGBA'))/255
        b=np.asarray(Image.open(root/f'native-{code}-albedo.png').convert('RGBA'))/255
        native=np.asarray(Image.open(root/f'native-{code}-mask.png').convert('RGBA'))
        actual_mask=a[:,:,3]>.5;native_mask=native[:,:,3]>127
        iou=float(np.sum(actual_mask&native_mask)/np.sum(actual_mask|native_mask))
        skin=binary_erosion(actual_mask&native_mask,iterations=2)
        # Eye materials differ between the independent Blender beauty setup
        # and Lie. Exclude the blue iris/scleral neighborhood, not skin seams.
        eyes=(b[:,:,2]>b[:,:,0]*1.08)&(b[:,:,2]>.15)&native_mask
        skin&=~binary_dilation(eyes,iterations=5)
        mae=float(np.abs(a[:,:,:3]-b[:,:,:3])[skin].mean())
        assert iou>=.985,(code,'silhouette',iou)
        assert mae<=.03,(code,'skin',mae)
        results.append({'case':code,'silhouette_iou':iou,'skin_rgb_mae':mae,'compared_pixels':int(skin.sum())})
    report={'cases':results,'min_silhouette_iou':min(r['silhouette_iou'] for r in results),'max_skin_rgb_mae':max(r['skin_rgb_mae'] for r in results)}
    (project/'lie24-native-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LIE24 NATIVE PASS',json.dumps(report));return report


if __name__=='__main__':compare(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'gpu_compute')
