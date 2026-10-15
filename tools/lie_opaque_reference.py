"""Independent float64 angular BRDF oracle and hemisphere quadrature.

The oracle uses explicit lambda/G and separate reflection vectors, whereas
GPU code evaluates the cancellation-free correlated Smith denominator.
Authored opaque nonmetal approximation; no measured material claims.
"""
from pathlib import Path
import json,math
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def normalized(v):
    v=np.asarray(v,dtype=np.float64);return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-10)
def fresnel(c,f0=.04):return f0+(1-f0)*(1-np.clip(c,0,1))**5
def filtered(rough,mean=1.,enabled=True):return min(max(rough,.2),.98)**4 if not enabled else min(min(max(rough,.2),.98)**4+min(max(1-mean,0),1),1)
def evaluate(albedo,rough,view,light,normal=(0,0,1),mean=1.,enabled=True,f0=.04,survival=1.):
    n=normalized(normal);v=normalized(view);l=normalized(light);nv=np.sum(n*v,axis=-1);nl=np.sum(n*l,axis=-1)
    half=v+l;valid=(nl>1e-6)&(nv>1e-6)&(np.sum(half*half,axis=-1)>1e-12)
    half=half/np.maximum(np.linalg.norm(half,axis=-1,keepdims=True),1e-30)
    nh=np.maximum(np.sum(n*half,axis=-1),0);vh=np.maximum(np.sum(v*half,axis=-1),0)
    a2=filtered(rough,mean,enabled)
    density=a2/(math.pi*(nh*nh*(a2-1)+1)**2)
    def lam(c):return .5*(np.sqrt(1+a2*np.maximum(1-c*c,0)/np.maximum(c*c,1e-30))-1)
    g=1/(1+lam(np.maximum(nv,1e-30))+lam(np.maximum(nl,1e-30)))
    spec=density*g*fresnel(vh,f0)/np.maximum(4*nl*nv,1e-30)*survival
    diff=(1-fresnel(nl,f0))*(1-fresnel(nv,f0))/math.pi
    value=np.asarray(albedo)*np.asarray(diff)[...,None]+np.asarray(spec)[...,None]
    return np.where(np.asarray(valid)[...,None],value,0.)
def energy(rough,nv,f0=.04,order=256):
    x,w=np.polynomial.legendre.leggauss(order);z=(x+1)/2;w=w/2
    phi=(np.arange(order*4)+.5)*2*math.pi/(order*4)
    l=np.stack(np.broadcast_arrays(np.sqrt(1-z[:,None]**2)*np.cos(phi),np.sqrt(1-z[:,None]**2)*np.sin(phi),z[:,None]),-1)
    v=(math.sqrt(1-nv*nv),0,nv)
    values=evaluate((1,1,1),rough,v,l,f0=f0)[...,0]*z[:,None]
    return float(np.sum(np.sum(values,axis=1)*w)*2*math.pi/(order*4))
def prepare():
    cases=[]
    def add(name,albedo,rough,view,light,normal=(0,0,1),mean=1.,enabled=True,f0=.04,survival=1.):
        data=list(albedo)+[rough]+list(view)+[0]+list(light)+[0]+list(normal)+[0]+[mean,float(enabled),f0,survival]
        cases.append(dict(name=name,input=data,expected=evaluate(albedo,rough,view,light,normal,mean,enabled,f0,survival).tolist()+[filtered(rough,mean,enabled)**.25]))
    for r in [.2,.35,.6,.9]:
        for nv in [.02,.3,1.]:
            v=(math.sqrt(1-nv*nv),0,nv)
            for light in [(0,0,1),(-.8,.1,.59),(.4,.5,.2)]:add(f'r{r}-nv{nv}-l{len(cases)}',(.35,.12,.04),r,v,light)
    add('source_on_receiver',(1,1,1),.6,(0,0,1),(0,0,0))
    add('zero_view',(1,1,1),.6,(0,0,0),(0,0,1))
    add('back_light',(1,1,1),.6,(0,0,1),(0,0,-1))
    add('back_view',(1,1,1),.6,(0,0,-1),(0,0,1))
    add('zero_albedo',(0,0,0),.35,(0,0,1),(.1,0,1))
    add('zero_survival',(0,0,0),.35,(0,0,1),(.1,0,1),survival=0.)
    for length in [1.,.99,.8,0.]:add('normal_variance_'+str(length),(.4,.2,.1),.3,(.4,0,1),(-.3,0,1),mean=length)
    add('filter_off',(.4,.2,.1),.3,(.4,0,1),(-.3,0,1),mean=.8,enabled=False)
    add('rotated_frame',(.7,.2,.1),.55,(1,.2,.1),(1,-.3,.4),normal=(1,0,0))
    target=ROOT/'gpu_compute/fixtures/opaque-reference.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(dict(schema='lie-opaque-reference/1',cases=cases),indent=2)+'\n')
    return cases
if __name__=='__main__':print(json.dumps({'cases':len(prepare())}))
