"""Independent float64 3x3 reference on explicit synthetic G-buffers."""
import json,math
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def cases():
    result={}
    for name in ['checker','instance_edge','group_edge','normal_edge','depth_edge','contrast_edge','open_hole']:
        projection=np.zeros((25,24),dtype='<f4');acc=np.zeros((25,8),dtype='<u4');owners=np.arange(25,dtype='<u4')
        for y in range(5):
            for x in range(5):
                i=y*5+x;v=projection[i];v[3]=1;v[6]=1;v[8:12]=[x+.5,y+.5,1,2]
                color=np.array([.35,.3,.25])+(.025 if (x+y)%2 else -.025)
                if x>2:
                    if name=='instance_edge':v[14]=1
                    if name=='group_edge':v[3]=2
                    if name=='normal_edge':v[4:7]=[0,1,0]
                    if name=='depth_edge':v[10]=1.03
                    if name=='contrast_edge':color[:]=.95
                acc[i,:3]=np.rint(color*10000);acc[i,3]=10000;acc[i,4:7]=np.rint((v[4:7]*.5+.5)*10000);acc[i,7]=8000
        if name=='open_hole':owners[12]=0xffffffff
        raw=np.c_[acc[:,:3]/10000,acc[:,7]/10000,acc[:,4:7]/10000*2-1,np.ones(25)]
        expected=np.zeros((25,8))
        for i in range(25):
            if owners[i]==0xffffffff:continue
            y,x=divmod(i,5);p=projection[i];weighted=np.zeros(8);total=0.
            for yy in range(max(0,y-1),min(5,y+2)):
                for xx in range(max(0,x-1),min(5,x+2)):
                    j=yy*5+xx;q=projection[j]
                    if owners[j]==0xffffffff or p[14]!=q[14] or p[3]!=q[3] or np.dot(p[4:7],q[4:7])<.95 or abs(float(p[10])-float(q[10]))>.002:continue
                    delta=raw[j,:3]-raw[i,:3];sigma=.35+.12*float(p[11]);w=math.exp(-((xx-x)**2+(yy-y)**2)/(2*sigma*sigma)-np.dot(delta,delta)/.0128)
                    weighted+=raw[j]*w;total+=w
            m=weighted/total;m[7]=min(np.linalg.norm(m[4:7]),1);expected[i]=m.astype('<f2').astype(float)
        result[name]={'acc_hex':acc.tobytes().hex(),'projection_hex':projection.tobytes().hex(),'owners_hex':owners.tobytes().hex(),'expected':expected.flatten().tolist(),'center_raw':raw[12].astype('<f2').astype(float).tolist()}
    return result
def prepare():
    result={'schema':'lie-filter-reference/1','cases':cases()};p=ROOT/'gpu_compute/fixtures/filter-reference.json';p.parent.mkdir(exist_ok=True);p.write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps({'cases':len(prepare()['cases'])}))
