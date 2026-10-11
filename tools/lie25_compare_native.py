"""Compare actual Lie pixels to independent rays against source geometry."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image


def compare(root):
    capture=root/'captures/anatomy25'
    master=json.loads((capture/'master.json').read_text())
    results=[]
    for mask in [15,14,12,8]:
        native=np.load(capture/f'native-mask{mask}.npz')['owners']
        actual=np.asarray(Image.open(root/f'lie25-unlit-mask{mask}.png').convert('RGBA'))/255
        expected_mask=native>=0;actual_mask=actual[:,:,3]>.5
        intersection=np.count_nonzero(expected_mask&actual_mask)
        union=np.count_nonzero(expected_mask|actual_mask)
        iou=intersection/max(union,1)
        expected=np.zeros_like(actual)
        for id in range(4):
            linear=np.asarray(master['palette'][id][:3]);linear=linear/(1+linear)
            rgb=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
            expected[native==id,:3]=rgb;expected[native==id,3]=1
        interior=expected_mask.copy()
        for dy,dx in [(0,2),(0,-2),(2,0),(-2,0)]:
            interior &= np.roll(native,(dy,dx),(0,1))==native
        interior &= actual_mask
        mae=float(np.abs(actual[interior,:3]-expected[interior,:3]).mean())
        Image.fromarray((expected*255).round().astype(np.uint8)).save(root/f'lie25-native-mask{mask}.png')
        results.append({'mask':mask,'silhouette_iou':float(iou),'interior_unlit_rgb_mae':mae,'interior_pixels':int(interior.sum()),'pass':bool(iou>=.985 and mae<=.03)})
    report={'cases':results,'passed':all(r['pass'] for r in results),'oracle':'Perspective rays against original high-resolution cropped surfaces in Blender BVH; no capture-point oracle.','limits':['rigid bust only','constant tissue pigments','no complete game gore','not a Cycles realism comparison']}
    (root/'lie25-native-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if not report['passed']:raise SystemExit(1)


if __name__=='__main__':compare(Path(sys.argv[1] if len(sys.argv)>1 else 'gpu_compute'))
