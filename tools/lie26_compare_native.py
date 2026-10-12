"""Compare Vulkan splats against independently posed original triangles."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion,label

def srgb(x):return np.where(x<=.0031308,12.92*x,1.055*np.maximum(x,0)**(1/2.4)-.055)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('project',type=Path);parser.add_argument('--record-only',action='store_true');args=parser.parse_args();project=args.project;root=project/'captures/anatomy26';master=json.loads((root/'master.json').read_text());fixture=json.loads((project/'fixtures/lie26-rig.json').read_text());cases=[]
    for case in master['cases']:
        native=np.load(root/f'native-{case["name"]}.npz');owners_native=native['owners'];native_covered=owners_native>=0;native_depth=native['depth'];
        if owners_native.shape==(1024,1024):
            coverage=native_covered.reshape(512,2,512,2).mean(axis=(1,3));expected=coverage>.5
            owners=np.where(expected,0 if case['mask']==15 else 2,-1)
            valid=native_covered.reshape(512,2,512,2);source_depth=np.where(native_covered,native_depth,0).reshape(512,2,512,2).sum(axis=(1,3))/np.maximum(valid.sum(axis=(1,3)),1)
        else:coverage=native_covered.astype(float);expected=native_covered;owners=owners_native;source_depth=native_depth
        actual=np.asarray(Image.open(project/f'lie26-{case["name"]}-unlit.png')).astype(float)/255;mask=actual[:,:,3]>.5
        union=np.count_nonzero(expected|mask);iou=np.count_nonzero(expected&mask)/max(union,1)
        interior=binary_erosion(expected,iterations=2)&binary_erosion(mask,iterations=2)
        color=np.zeros_like(actual);palette=np.asarray(master['palette'])[:,:3];converted=srgb(palette/(1+palette));color[coverage>0,:3]=converted[0 if case['mask']==15 else 2];color[:,:,3]=coverage
        Image.fromarray(np.rint(color*255).astype(np.uint8),'RGBA').save(project/f'lie26-{case["name"]}-native.png')
        rgb_mae=float(np.mean(np.abs(actual[interior,:3]-color[interior,:3])))
        subdepth=np.fromfile(project/f'lie26-{case["name"]}-depth.bin',dtype='<f4').reshape(1024,1024).reshape(512,2,512,2);valid=subdepth<10;depth=np.where(valid,subdepth,0).sum(axis=(1,3))/np.maximum(valid.sum(axis=(1,3)),1)
        errors=np.abs(depth[interior]-source_depth[interior]);depth_mae=float(np.mean(errors));depth_p95=float(np.percentile(errors,95))
        patches=[];angle=math.radians(case['camera_yaw']);target=np.array([0,.82,.09]);eye=target+np.array([math.sin(angle),0,math.cos(angle)])*3.5;right=np.array([math.cos(angle),0,-math.sin(angle)]);forward=(target-eye)/3.5;tangent=math.tan(math.radians(35)/2)
        anchors=next(c['origins'] for c in fixture['cases'] if c['name']==case['name'])
        for bid in [3,4,6,7,9,10,12,13]:
            p=np.asarray(anchors[bid])-eye;z=p@forward;px=int((p@right/z/tangent+1)*256);py=int((1-p[1]/z/tangent)*256);x0=max(px-22,0);x1=min(px+22,512);y0=max(py-22,0);y1=min(py+22,512)
            e=expected[y0:y1,x0:x1];a=mask[y0:y1,x0:x1];u=np.count_nonzero(e|a);score=np.count_nonzero(e&a)/max(u,1)
            holes=e&~a;components,n=label(holes);max_hole=max(np.bincount(components.ravel())[1:],default=0)
            patches.append(dict(bone=master['bones'][bid]['name'],iou=float(score),missing_pixels=int(holes.sum()),largest_missing_component=int(max_hole)))
        passed=bool(iou>=.98 and rgb_mae<=.03 and depth_mae<=.003 and depth_p95<=.008 and all(p['iou']>=.96 for p in patches))
        result=dict(name=case['name'],silhouette_iou=float(iou),rgb_mae=rgb_mae,depth_mae_m=depth_mae,depth_p95_m=depth_p95,joint_patches=patches,passed=passed);cases.append(result);print(json.dumps(result))
    result=dict(passed=all(c['passed'] for c in cases),sample_count=master['sample_count'],sample_sha256=master['buffers']['samples.bin']['sha256'],shader_sha256=hashlib.file_digest((project/'shaders/lie26_motion.glsl').open('rb'),'sha256').hexdigest(),thresholds=dict(silhouette_iou=.98,joint_patch_iou=.96,rgb_mae=.03,depth_mae_m=.003,depth_p95_m=.008),cases=cases)
    (project/'lie26-native-comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    raise SystemExit(0 if result['passed'] or args.record_only else 1)

if __name__=='__main__':main()
