"""Float64 reference for source-scoped convex irradiance interpolation.

This is reconstruction of solved irradiance, not a new light, BSDF or solver.
Groups explicitly declare owner/material/surface compatibility.
"""
import numpy as np

def weights(point,node,positions,normals,groups,enabled=True,areas=None):
    p=np.asarray(positions,float);n=np.asarray(normals,float);g=np.asarray(groups,int)
    start,count=map(int,g[node][:2]);out=np.zeros(len(p))
    epsilon=1e-6 if areas is None else max(float(areas[node])*1e-4,1e-12)
    if not enabled or count==1:out[node]=1.;return out
    reference=n[node]/np.linalg.norm(n[node])
    for k in range(start,start+count):
        normal=n[k]/np.linalg.norm(n[k]);agreement=reference@normal
        if agreement<.9:continue
        delta=np.asarray(point)-p[k];tangent=delta-reference*(delta@reference)
        out[k]=max((agreement-.9)/.1,0)**2/(tangent@tangent+epsilon)
    if out.sum()<=0:out[node]=1
    return out/out.sum()
