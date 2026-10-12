"""Derive a shared world bank without changing either validated source bank."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import numpy as np

BUILDING_MASTERS=('wall','door_base','door_head','window_wall','corner','slab','lintel')

def atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+'.tmp');temporary.write_bytes(data);os.replace(temporary,path)

def prepare(root,robot_bank='robot_refined'):
    root=Path(root);out=root/'captures/robot_world';robot_root=root/'captures'/robot_bank;building_root=root/'captures/building28'
    sources=[]
    def source(directory):
        catalog=json.loads((directory/'catalog.json').read_text());raw=(directory/'library.bin').read_bytes()
        assert len(raw)==catalog['bytes']==catalog['sample_count']*catalog['stride']
        assert hashlib.sha256(raw).hexdigest()==catalog['sha256']
        sources.append(dict(path=str(directory.relative_to(root)),sha256=catalog['sha256'],bytes=len(raw),stride=catalog['stride']))
        return catalog,raw
    robot,raw=source(robot_root);building,braw=source(building_root)
    catalog=copy.deepcopy(robot);catalog['sources']=sources;catalog['building_lod']=1;catalog['materials']+=building['materials']
    pieces=[np.frombuffer(raw,dtype='<f4').reshape(-1,24).copy()];cursor=robot['sample_count']
    source_points=0
    for name in BUILDING_MASTERS:
        level=building['masters'][name]['levels'][1]
        old=np.frombuffer(braw,dtype='<f4').reshape(-1,20)[level['start']:level['start']+level['count']]
        new=np.zeros((len(old),24),dtype='<f4');new[:,:20]=old;new[:,8]+=16;new[:,11]=0;new[:,15]=0;new[:,20:23]=old[:,4:7]
        assert np.array_equal(new[:,:8],old[:,:8]) and np.array_equal(new[:,12:15],old[:,12:15])
        assert np.array_equal(new[:,16:20],old[:,16:20]) and np.array_equal(new[:,10],old[:,10])
        metadata=copy.deepcopy(building['masters'][name]);metadata['levels']=[dict(start=cursor,count=len(new))]*2
        metadata['source_master']=name;metadata['source_lod']=1
        catalog['masters']['house_'+name]=metadata;pieces.append(new);cursor+=len(new);source_points+=len(new)
    merged=np.concatenate(pieces).tobytes();assert len(merged)<=64*1024*1024
    catalog.update(sample_count=cursor,bytes=len(merged),sha256=hashlib.sha256(merged).hexdigest())
    # Exact original triangle surfaces are collision geometry only, never drawn.
    oracles=json.loads((root/'assets/lie28/source-surfaces.json').read_text())
    robot_oracle=json.loads((root/'assets/robot_modular/source-surfaces.json').read_text())
    faces=[];collision={};vertex_start=0
    for name,mesh in [('house_'+n,oracles[n]) for n in BUILDING_MASTERS]+[('ground',robot_oracle['ground'])]:
        vertices=np.asarray(mesh['vertices'],dtype='<f4');triangles=np.asarray(mesh['triangles'],dtype=int)
        points=vertices[triangles].reshape(-1,3);assert np.isfinite(points).all()
        collision[name]=dict(start=vertex_start,count=len(points));vertex_start+=len(points);faces.append(points)
    collision_bytes=np.concatenate(faces).astype('<f4').tobytes()
    catalog['collision']=dict(file='collision.bin',bytes=len(collision_bytes),sha256=hashlib.sha256(collision_bytes).hexdigest(),faces=collision,
        source_sha256=hashlib.sha256((root/'assets/lie28/source-surfaces.json').read_bytes()).hexdigest())
    atomic(out/'library.bin',merged);atomic(out/'collision.bin',collision_bytes)
    atomic(out/'catalog.json',(json.dumps(catalog,indent=2)+'\n').encode())
    report=dict(robot_samples_unchanged=robot['sample_count'],building_samples_exactly_converted=source_points,bytes=len(merged),samples=cursor,sha256=catalog['sha256'],collision_triangles=vertex_start//3,collision_source='Original authored triangles; no convex hull sealing door/window holes',original_mesh_drawn=False)
    atomic(root/'robot-world-bank-verification.json',(json.dumps(report,indent=2)+'\n').encode());print(json.dumps(report))
    return catalog

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]/'gpu_compute');parser.add_argument('--robot-bank',default='robot_refined');args=parser.parse_args();prepare(args.root,args.robot_bank)
