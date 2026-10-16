"""Reproducible offline source-BLAS probe; not Vulkan or physical FPS."""
import json,struct,time,sys
from pathlib import Path
import numpy as np
import argparse
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie_tangent_bounds import refit
parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]/'gpu_compute/captures/liewall06');parser.add_argument('--output',type=Path);args=parser.parse_args()
root=args.root
raw=(root/'library.bin').read_bytes();a=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
original=(root/'surface-bvh.bin').read_bytes();leaf_bytes=(root/'surface-leaves.bin').read_bytes()
source=json.loads((root/'surface-source.json').read_text());cat=json.loads((root/'catalog.json').read_text())
import hashlib
assert hashlib.sha256(raw).hexdigest()==cat['sha256']==source['source_bank_sha256']
assert hashlib.sha256(original).hexdigest()==source['packets']['nodes']['sha256'] and hashlib.sha256(leaf_bytes).hexdigest()==source['packets']['leaves']['sha256']
nodes=np.frombuffer(original,dtype='<f4').reshape(-1,8);words=np.frombuffer(original,dtype='<u4').reshape(-1,8);refs=np.frombuffer(leaf_bytes,dtype='<u4');tight=np.frombuffer(refit(a,original,leaf_bytes),dtype='<f4').reshape(-1,8)
p=a[:,:3].astype(float);n=a[:,4:7].astype(float)
# Keep inputs fixed before observing any result; classify all rays, no outliers.
rng=np.random.default_rng(16017);master=source["roots"][0];ids=rng.choice(np.arange(master["start"],master["start"]+master["count"]),min(1200,master["count"]),replace=False)
def walk(boxes,o,d,source):
 i=int(master["root"]);end=int(words[i,3]);nearest=.025;nc=0;dc=0
 while i<end:
  nc+=1;row=boxes[i];enter=.0003;leave=nearest
  for k in range(3):
   if abs(d[k])<1e-12:
    if o[k]<row[k] or o[k]>row[k+4]:enter=1.;leave=0.;break
   else:
    aa=(row[k]-o[k])/d[k];bb=(row[k+4]-o[k])/d[k];enter=max(enter,min(aa,bb));leave=min(leave,max(aa,bb))
  if enter>leave:i=int(words[i,3]);continue
  leaf=int(words[i,7])
  if leaf==0xffffffff:i+=1;continue
  for sid in refs[leaf+1:leaf+1+int(refs[leaf])]:
   dc+=1
   if sid==source:continue
   sample=a[sid];normal=sample[4:7].astype(float);denom=normal@d
   if abs(denom)<1e-8:continue
   t=normal@(sample[:3]-o)/denom
   if t<=.0003 or t>=nearest:continue
   delta=o+t*d-sample[:3]
   if delta@delta>float(sample[3])**2:continue
   nearest=t
   if nearest<=.75*.025:return 0.,nc,dc
  i=int(words[i,3])
 u=np.clip((nearest-.75*.025)/(.25*.025),0,1);return u*u*(3-2*u),nc,dc
counts=np.zeros((2,2),dtype=np.int64);errors=[];launched=0
for sid in ids:
 point=p[sid];normal=n[sid];light=np.array([-.4,.3,.5]);d=light-point;d/=np.linalg.norm(d)
 if normal@d<=0:continue
 launched+=1;o=point+normal*.0003
 before=walk(nodes,o,d,sid);after=walk(tight,o,d,sid)
 counts[0]+=before[1:];counts[1]+=after[1:]
 if abs(before[0]-after[0])>1e-12:errors.append([int(sid),before[0],after[0]])
result={'schema':'lie-tangent-bounds-probe/1','scope':'offline float64 BLAS probe only; one source master; fixed random source IDs and light; no TLAS, no display, no Vulkan or Android timing; original topology/order/disks','candidates':len(ids),'launched':launched,'reference_nodes':int(counts[0,0]),'tight_nodes':int(counts[1,0]),'reference_disks':int(counts[0,1]),'tight_disks':int(counts[1,1]),'max_visibility_difference':max([abs(x[1]-x[2]) for x in errors],default=0),'differences':errors,'nodes':len(nodes),'source_bank_sha256':json.loads((root/'catalog.json').read_text())['sha256']}
if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result));sys.exit(1 if errors else 0)
