"""Untimed float64 ray oracle independent of raster triangle coverage."""
import json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]/'gpu_compute/captures/liewall06'


def trace(eye,dirs,proxies):
 n=len(dirs); best=np.full(n,np.inf);owner=np.zeros(n);second=np.full(n,np.inf);best_edge=np.full(n,np.inf)
 for instance in range(97):
  packet=proxies[instance]
  inv=packet[16:32].reshape(4,4).T.astype(float)
  o=inv[:3,:3]@eye+inv[:3,3];r=dirs@inv[:3,:3].T
  lo=packet[32:35].astype(float);hi=packet[36:39].astype(float)
  box=proof['boxes'][0 if instance<96 else 1]
  safe=np.where(abs(r)>1e-14,r,np.where(r<0,-1e-14,1e-14))
  near=np.minimum((lo-o)/safe,(hi-o)/safe);far=np.maximum((lo-o)/safe,(hi-o)/safe)
  start=np.maximum(near.max(axis=1),0);end=far.min(axis=1)
  entry_axis=near.argmax(axis=1);face=entry_axis*2+(r[np.arange(n),entry_axis]>0)
  for fi in range(6):
   ids=np.flatnonzero((face==fi)&(end>=start)&(start<best))
   if not len(ids):continue
   axis=fi//2;ax=[k for k in range(3) if k!=axis]
   rect=proof['faces'][box['first_face']+fi];w,h=rect['width'],rect['height'];offset=np.array([rect['x'],rect['y']])
   cellsize=(hi[ax]-lo[ax])/[w,h]
   t=start[ids].copy()+1e-10
   for step in range(w+h+4):
    if not len(ids):break
    pos=o+t[:,None]*r[ids]
    cell=np.clip(np.floor((pos[:,ax]-lo[ax])/cellsize).astype(int),0,[w-1,h-1])
    edge=lo[ax]+(cell+(r[ids][:,ax]>=0))*cellsize
    uv_r=r[ids][:,ax]
    next_t=np.divide(edge-pos[:,ax],uv_r,out=np.full_like(uv_r,np.inf),where=abs(uv_r)>1e-14)+t[:,None]
    stop=np.minimum(end[ids],next_t.min(axis=1))
    atlas=cell+offset
    d=field[atlas[:,1],atlas[:,0]].astype(float)
    coord=(hi[axis]-d) if fi%2==0 else (lo[axis]+d)
    cand=(coord-o[axis])/r[ids,axis,None]
    cand[(d<0)|(cand<t[:,None]-1e-9)|(cand>stop[:,None]+1e-9)]=np.inf
    layer=cand.argmin(axis=1);z=cand[np.arange(len(ids)),layer];hit=np.isfinite(z)
    if hit.any():
     ix=ids[hit];zz=z[hit];old=best[ix].copy()
     wins=zz<old
     second[ix]=np.minimum(second[ix],np.maximum(old,zz))
     best[ix[wins]]=zz[wins]
     point=o+r[ix[wins]]*zz[wins,None]
     uv=(point[:,ax]-lo[ax])/cellsize
     fraction=uv-np.floor(uv)
     best_edge[ix[wins]]=np.min(np.minimum(fraction,1-fraction)*cellsize,axis=1)
     a=atlas[hit][wins];L=layer[hit][wins]
     owner[ix[wins]]=normal[L,a[:,1],a[:,0],3].astype(float)+float(packet[42])+1
    t=np.maximum(stop+1e-10,t+1e-10)
    active=(~hit)&(t<=end[ids]+1e-9)
    ids=ids[active];t=t[active]
 return best,owner,second,best_edge

if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser()
 parser.add_argument('--captures',type=Path,default=Path('/tmp/lie-native-qa/native-depth'))
 parser.add_argument('--bank',type=Path,default=ROOT)
 parser.add_argument('--output',type=Path,default=Path('/tmp/lie-oracle-final.json'))
 args=parser.parse_args()
 ROOT=args.bank;p=ROOT/'direct';proof=json.loads((p/'surface.json').read_text());cat=json.loads((ROOT/'catalog.json').read_text())
 field=np.fromfile(p/'depth.bin','<f4').reshape(proof['height'],proof['width'],4)
 normal=np.fromfile(p/'normal.bin','<f2').reshape(4,proof['height'],proof['width'],4)
 root=args.captures
 a=np.fromfile(root/'0-regions-world.bin','<f4').reshape(-1,4)
 b=np.fromfile(root/'0-native-world.bin','<f4').reshape(-1,4)
 both=(a[:,3]>.5)&(b[:,3]>.5)
 changed=(a[:,3]!=b[:,3])
 rng=np.random.default_rng(343)
 valid=np.flatnonzero(both&~changed);background=np.flatnonzero((a[:,3]<.5)&(b[:,3]<.5))
 ids=np.unique(np.r_[np.flatnonzero(changed),rng.choice(valid,min(1200,len(valid)),replace=False),rng.choice(background,min(1200,len(background)),replace=False)])
 proxies=np.fromfile(root/'0-native-proxies.bin','<f4').reshape(97,48)
 view=np.fromfile(root/'0-native-views.bin','<f4')[:20].astype(float)
 eye=view[:3];size=round(np.sqrt(len(a)))
 xy=np.c_[ids%size+.5,ids//size+.5]*(2/size)-1
 dirs=view[12:15]+(view[4:7]*xy[:,0,None]-view[8:11]*xy[:,1,None])*view[18]
 dirs/=np.linalg.norm(dirs,axis=1)[:,None]
 z,owner,second,edge=trace(eye,dirs,proxies)
 hits=np.isfinite(z);native_hits=b[ids,3]>.5
 overlap=hits&native_hits
 actual=np.linalg.norm(b[ids,:3]-eye,axis=1)
 err=abs(z[overlap]-actual[overlap])
 result={'scope':'independent float64 exact finite captured-cell ray oracle; all regions/native ownership or coverage differences plus seeded hit and empty rays; original runtime view/proxy packets; regions is not ground truth; no source-mesh or mobile-performance claim',
 'samples':len(ids),'oracle_hits':int(hits.sum()),'native_hits':int(native_hits.sum()),
 'native_missing':int((hits&~native_hits).sum()),'native_extra':int((~hits&native_hits).sum()),
 'native_owner_mismatches':int(((owner!=b[ids,3])&overlap).sum()),
 'owner_mismatch_distance_to_cell_edge_m':edge[(owner!=b[ids,3])&overlap].tolist(),
 'regions_owner_mismatches':int(((owner!=a[ids,3])&hits&(a[ids,3]>.5)).sum()),
 'native_distance_error_m_percentiles':np.percentile(err,[50,90,99,100]).tolist(),
 'native_distance_errors_over_20um':int((err>2e-5).sum()),
 'near_ties_under_1um':int((second[hits]-z[hits]<1e-6).sum())}
 print(json.dumps(result,indent=2));args.output.write_text(json.dumps(result,indent=2)+'\n')
