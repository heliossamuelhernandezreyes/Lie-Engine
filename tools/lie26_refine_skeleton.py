"""Refine thin anatomical bone captures without recapturing other layers."""
import argparse,gc,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie26_prepare_blender import capture
from lie26_motion import rig

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--resolution',type=int,default=144);p.add_argument('--head-resolution',type=int,default=224);args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.root;master=json.loads((root/'master.json').read_text());bones=rig();old=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20);layer=master['layers'][2];start=layer['sample_offset'];end=start+layer['sample_count'];blocks=[];metadata=[]
    for bid in range(15):
        source=np.load(root/f'source-2-{bid}.npz');resolution=args.head_resolution if bid==2 else args.resolution
        rows,views=capture(source['points'],source['faces'],bones,2,bid,root,resolution);rows[:,7]*=.38/.45;blocks.append(rows);metadata.append(dict(layer=2,bone=bid,pose={},resolution=resolution,views=views,samples=len(rows)))
        del source;gc.collect();print('REFINE26',bid,sum(len(b) for b in blocks),flush=True)
    count=sum(len(b) for b in blocks);data=np.concatenate([old[:start],*blocks,old[end:]])
    if len(data)>6000000:raise ValueError('Refined bank exceeds 6M contract')
    path=root/'samples.pending.bin';path.write_bytes(data.astype('<f4').tobytes());path.replace(root/'samples.bin');layer['sample_count']=count;master['layers'][3]['sample_offset']=start+count;master['sample_count']=master['invocation_count']=len(data);master['skeleton_footprint_scale']=.38;master['capture_views']=[v for v in master['capture_views'] if v['layer']!=2]+metadata;master['buffers']['samples.bin']=dict(bytes=(root/'samples.bin').stat().st_size,sha256=hashlib.file_digest((root/'samples.bin').open('rb'),'sha256').hexdigest());(root/'master.json').write_text(json.dumps(master,indent=2)+'\n');print('REFINED_MASTER26',len(data),flush=True)

if __name__=='__main__':main()
