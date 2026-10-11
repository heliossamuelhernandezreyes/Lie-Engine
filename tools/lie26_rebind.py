"""Rebind existing source-space capture hits without recapturing imagery.

Offline segmentation captures remain reusable when the authored weight field
changes. Original skeleton meshes keep their semantic rigid assignments.
"""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from lie26_motion import rig,bindings

def main():
    parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);parser.add_argument('--keep-sparse',action='store_true');args=parser.parse_args();root=args.root;bones=rig();master=json.loads((root/'master.json').read_text());
    if master.get('sparse_joint_bindings') and not args.keep_sparse:raise ValueError('Rebind before sparse joint binding')
    data=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20)
    for layer in master['layers']:
        lid=layer['id'];start=layer['sample_offset'];end=start+layer['sample_count']
        if lid!=2:
            for begin in range(start,end,100000):
                rows=data[begin:min(begin+100000,end)];direct=rows[:,3]>=0;first,second,weight,gradient=bindings(rows[direct,:3],bones);rows[direct,3]=first;rows[direct,14]=second;rows[direct,13]=weight;rows[direct,9:12]=gradient
        else:data[start:end,7]*=float(master.get("skeleton_footprint_scale",.27))/float(master.get("skeleton_footprint_scale",.45))
        for path in root.glob(f'source-{lid}-*.npz'):
            if '.pending.' in path.name:continue
            source=np.load(path);values={key:source[key] for key in source.files};source.close()
            if lid!=2:
                first,second,weight,_=bindings(values['points'],bones);values.update(first=first.astype(np.int32),second=second.astype(np.int32),weight=weight.astype(np.float32))
                temporary=path.with_suffix('.pending.npz');np.savez_compressed(temporary,**values);temporary.replace(path)
        print('REBIND26',lid,flush=True)
    if master.get('sparse_joint_bindings'):
        vertices=np.fromfile(root/'vertices.bin',dtype='<f4').reshape(-1,24);a,b,w,_=bindings(vertices[8:,:3],bones);vertices[8:,3]=a;vertices[8:,4]=b;vertices[8:,5]=w
        temporary=root/'vertices.pending.bin';temporary.write_bytes(vertices.tobytes());temporary.replace(root/'vertices.bin');master['buffers']['vertices.bin']=dict(bytes=(root/'vertices.bin').stat().st_size,sha256=hashlib.file_digest((root/'vertices.bin').open('rb'),'sha256').hexdigest())
    temporary=root/'samples.pending.bin';temporary.write_bytes(data.tobytes());temporary.replace(root/'samples.bin');master['bones']=bones;master['buffers']['samples.bin']=dict(bytes=(root/'samples.bin').stat().st_size,sha256=hashlib.file_digest((root/'samples.bin').open('rb'),'sha256').hexdigest());master['skeleton_footprint_scale']=float(master.get('skeleton_footprint_scale',.27))
    (root/'master.json').write_text(json.dumps(master,indent=2)+'\n')

if __name__=='__main__':main()
