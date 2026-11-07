"""Float64 vector segment/AABB queries, no assembly or source recipes."""
import numpy as np

def clear_segments(a,b,boxes,owners_a=None,owners_b=None):
    """Vector slab reference, bounded memory, endpoint margin matches field ABI."""
    a=np.asarray(a);b=np.asarray(b);boxes=np.asarray(boxes).reshape(-1,2,3);out=np.ones(len(a),bool)
    for start in range(0,len(a),128):
        stop=min(start+128,len(a));p=a[start:stop,None,:];d=(b[start:stop]-a[start:stop])[:,None,:];parallel=abs(d)<1e-8;denom=np.where(parallel,1,d);u=(boxes[None,:,0]-p)/denom;v=(boxes[None,:,1]-p)/denom
        near=np.maximum(np.where(parallel,-np.inf,np.minimum(u,v)).max(-1),.001);far=np.minimum(np.where(parallel,np.inf,np.maximum(u,v)).min(-1),.999);hit=(near<=far)&~(parallel&((p<boxes[None,:,0])|(p>boxes[None,:,1]))).any(-1)
        for owners in [owners_a,owners_b]:
            if owners is not None:
                ids=np.asarray(owners[start:stop],int);valid=(ids>=0)&(ids<len(boxes));hit[np.arange(stop-start)[valid],ids[valid]]=False
        out[start:stop]=~hit.any(1)
    return out

