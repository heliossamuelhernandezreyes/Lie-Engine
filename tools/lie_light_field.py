"""Independent float64 finite-patch oracle, with source-separated directions.

This deliberately uses array scatter/reductions, not the GPU gather algorithm.
Positions/areas are metric; powers are relative linear RGB. Opaque response is
passive diffuse + approximate glossy, with one moment/source/surface/bounce.
"""
import copy,hashlib,json,math
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]

def unit(x,fallback=None):
    x=np.asarray(x,float);length=np.linalg.norm(x,axis=-1,keepdims=True)
    out=x/np.maximum(length,1e-30)
    if fallback is not None:out=np.where(length>1e-8,out,fallback)
    return out

def csr(matrix,incoming=False):
    a=np.asarray(matrix,dtype='<f4');n=len(a);offset=[0];edges=bytearray()
    for i in range(n):
        for j in range(n):
            v=a[j,i] if incoming else a[i,j]
            if v>0:edges+=np.array([j],dtype='<u4').tobytes()+np.array([v],dtype='<f4').tobytes()
        offset.append(len(edges)//8)
    return np.array([n,len(edges)//8,4,n+5,*offset],dtype='<u4').tobytes()+edges

def decode_csr(raw):
    a=np.frombuffer(raw,dtype='<u4');n,m,ob,eb=map(int,a[:4]);rows=[];cols=[];weights=[]
    if ob!=4 or eb!=n+5 or len(a)!=n+5+2*m:raise ValueError('CSR shape')
    for i in range(n):
        for j in range(int(a[ob+i]),int(a[ob+i+1])):
            rows.append(i);cols.append(int(a[eb+2*j]));weights.append(float(a[eb+2*j+1:eb+2*j+2].view('<f4')[0]))
    return np.array(rows,int),np.array(cols,int),np.array(weights)

def sources(model, matrix, optical=None, boxes=(), owners=None, planes=None):
    n=len(model['patches']);p=model['patches']
    if optical is None:
        optical=np.zeros((n,16),dtype='<f4')
        for i,patch in enumerate(p):
            material=model['materials'][patch['material']]
            optical[i,:3]=material.get('albedo',[.7,.7,.7]);optical[i,3]=material.get('roughness',.6)
            optical[i,4]=material.get('metallic',0);optical[i,6]=material.get('ior',1.5);optical[i,12:15]=patch['normal']
    boxes=np.asarray(boxes,dtype=float).reshape(-1,2,3);nb=len(boxes)
    boxrows=np.zeros((max(nb,1),8),dtype='<f4')
    if nb:boxrows[:,[0,1,2,4,5,6]]=boxes.reshape(nb,6)
    if owners is None:owners=np.full(n,0xffffffff,dtype='<u4')
    if planes is None:planes=np.tile([0.,0.,1.,1e6],(max(nb,1),1))
    return {'factors':csr(matrix,True),'outgoing':csr(matrix),'optics':np.array([1,n,1,1],dtype='<u4').tobytes()+np.asarray(optical,dtype='<f4').tobytes(),
            'boxes':np.array([nb,0,0,0],dtype='<u4').tobytes()+boxrows.tobytes(),'owners':np.asarray(owners,dtype='<u4').tobytes(),'planes':np.asarray(planes,dtype='<f4').tobytes()}

def hit_box(a,b,low,high,plane=None):
    near,far=.001,.999;delta=b-a
    for k in range(3):
        if abs(delta[k])<1e-8:
            if a[k]<low[k] or a[k]>high[k]:return False
        else:
            u,v=(low[k]-a[k])/delta[k],(high[k]-a[k])/delta[k]
            near=max(near,min(u,v));far=min(far,max(u,v))
    if plane is not None and near<=far:
        side=float(np.dot(plane[:3],a)-plane[3]);rate=float(np.dot(plane[:3],delta))
        if abs(rate)<1e-9:
            if side>0:return False
        elif rate>0:far=min(far,-side/rate)
        else:near=max(near,-side/rate)
    return near<=far

def visible(a,b,node,model,packets,scan_caps=True):
    for low,high in model.get('blockers',[]):
        if hit_box(a,b,np.array(low),np.array(high)):return False
    d=b-a
    for tri in model.get('triangles',[]):
        v0,v1,v2=np.asarray(tri);e1,e2=v1-v0,v2-v0;h=np.cross(d,e2);det=np.dot(e1,h)
        if abs(det)<1e-8:continue
        s=a-v0;u=np.dot(s,h)/det;q=np.cross(s,e1);v=np.dot(d,q)/det;t=np.dot(e2,q)/det
        if 0<=u<=1 and 0<=v and u+v<=1 and .001<=t<=.999:return False
    nb=int(np.frombuffer(packets['boxes'],dtype='<u4')[0]);boxes=np.frombuffer(packets['boxes'],dtype='<f4')[4:].reshape(-1,8)
    owners=np.frombuffer(packets['owners'],dtype='<u4');planes=np.frombuffer(packets['planes'],dtype='<f4').reshape(-1,4)
    for k in range(nb):
        if k!=owners[node] and hit_box(a,b,boxes[k,:3],boxes[k,4:7],planes[k] if scan_caps else None):return False
    return True

def solve(model,packets,separate=True,scan_caps=True):
    if model.get('optical_sheets'):raise ValueError('Oracle covers opaque paths only')
    patches=model['patches'];n=len(patches);L=len(model['lights'])
    if not 1<=n<=1024 or not 1<=L<=8:raise ValueError('Field capacity')
    p=np.asarray([v['position'] for v in patches],dtype='<f4').astype(float)
    normals=np.asarray([v['normal'] for v in patches],dtype='<f4').astype(float)
    areas=np.asarray([v['area'] for v in patches],dtype='<f4').astype(float)
    optics=np.frombuffer(packets['optics'],dtype='<f4')[4:].reshape(n,16).astype(float)
    absorption=np.array([model['materials'][v['material']]['absorption_code']/1000 for v in patches],dtype='<f4').astype(float)
    gray=np.array([v['gray_mean'] for v in patches]);tint=np.array([model['materials'][v['material']]['tint_linear'] for v in patches])
    rho=tint*(1-absorption[:,None])*gray[:,None]
    on=unit(optics[:,12:15]);albedo=optics[:,:3];metal=optics[:,4,None];ior=optics[:,6,None]
    src,dst,F=decode_csr(packets['outgoing']);delta=p[dst]-p[src];dist=np.linalg.norm(delta,axis=1);directions=unit(delta)
    baseline=np.maximum(np.sum(normals[src]*directions,axis=1),1e-6);diffuse=np.maximum(np.sum(on[src]*directions,axis=1),0)
    rough=np.maximum(optics[:,3],.025);expo=np.clip(2/rough**2-2,1,2048)
    policy=model.get('secondary_radii');bounces=int(model.get('bounces',2))
    def parts(travel):
        ci=np.clip(-np.sum(on*travel,axis=1),0,1)[:,None]
        f0=(1-metal)*((ior-1)/(ior+1))**2+metal*albedo
        fresnel=f0+(1-f0)*(1-ci)**5
        d=(1-metal)*(1-fresnel)*albedo*(1-absorption[:,None]);r=fresnel*(1-absorption[:,None])
        cap=np.maximum(1,d+r);d=np.where(ci>1e-8,d/cap,0);r=np.where(ci>1e-8,r/cap,0)
        return d,r
    def radius(parent,flux):
        if not policy:return np.zeros(n)
        e=np.max(flux,axis=1);scale=np.array([model['materials'][v['material']].get('radius_scale',1) for v in patches])
        maximum=policy['radius_max'];decay=policy['radius_decay']
        if policy['mode']=='irradiance':r=np.minimum(parent*decay,np.sqrt(e/(math.pi*policy['irradiance_cutoff'])))
        else:r=np.minimum(parent*decay*np.sqrt(np.max(rho,axis=1)),maximum*np.sqrt(e/policy['power_reference']))
        return np.minimum(r,maximum)*scale
    direct=[];travels=[];parents=[]
    for light in model['lights']:
        lamp=np.asarray(light['position'],dtype='<f4').astype(float);power=np.asarray(light['power_rgb'],dtype='<f4').astype(float)
        span=lamp-p;d2=np.sum(span*span,axis=1);cosine=np.maximum(np.sum(normals*unit(span),axis=1),0)
        fade=np.maximum(0,1-(np.sqrt(d2)/float(light['radius']))**4)**2
        w=areas*cosine*fade/(4*math.pi*np.maximum(d2,.0025));w=np.where(d2>1e-10,w,0)
        for i in range(n):
            if w[i]>0 and not visible(p[i],lamp,i,model,packets,scan_caps):w[i]=0
        flux=w[:,None]*power/max(1,float(w.sum()));direct.append(flux);travels.append(unit(p-lamp,fallback=-normals));parents.append(np.where(flux.max(1)>0,light['radius'],0))
    direct=np.asarray(direct);travels=np.asarray(travels);parents=np.asarray(parents)
    if not separate:
        strength=direct.max(2);travels=unit(np.sum(travels*strength[:,:,None],axis=0),fallback=-normals)[None]
        direct=direct.sum(0,keepdims=True);parents=parents.max(0,keepdims=True)
    incoming=direct.copy();total=direct.copy();radii=np.stack([radius(parent,f*(sum(parts(t)))) for parent,f,t in zip(parents,incoming,travels)])
    generations=[incoming.sum((0,1)).tolist()];channels=[incoming.sum(1).tolist()]
    for _ in range(bounces):
        next_power=[];next_travel=[];next_radii=[]
        for frontier,travel,reach in zip(incoming,travels,radii):
            d,r=parts(travel);mirrored=travel-2*np.sum(travel*on,axis=1)[:,None]*on
            gloss=np.where(diffuse>0,np.maximum(np.sum(mirrored[src]*directions,axis=1),0)**expo[src],0)
            fade=np.where(reach[src]>0,np.maximum(0,1-(dist/np.maximum(reach[src],1e-30))**4)**2,0) if policy else np.ones(len(F))
            weights=F[:,None]*np.stack([diffuse,gloss],axis=1)/baseline[:,None]*fade[:,None]
            caps=np.zeros((n,2));np.add.at(caps,src,weights);weights/=np.maximum(caps[src],1)
            links=frontier[src]*(d[src]*weights[:,0,None]+r[src]*weights[:,1,None])
            flux=np.zeros((n,3));moment=np.zeros((n,3));parent=np.zeros(n)
            np.add.at(flux,dst,links);np.add.at(moment,dst,directions*links.max(1)[:,None]);np.maximum.at(parent,dst,np.where(links.max(1)>0,reach[src],0))
            nt=unit(moment,fallback=-normals);next_power.append(flux);next_travel.append(nt);next_radii.append(radius(parent,flux*sum(parts(nt))))
            if (flux.sum(0)>frontier.sum(0)+1e-9).any():raise AssertionError('Passive per-source generation bound')
        incoming=np.asarray(next_power);travels=np.asarray(next_travel);radii=np.asarray(next_radii);total+=incoming
        generations.append(incoming.sum((0,1)).tolist());channels.append(incoming.sum(1).tolist())
    return {'flux':total.sum(0).tolist(),'frontier':incoming.sum(0).tolist(),'generation_totals_rgb':generations,'channel_totals_by_generation':channels,'irradiance':(total.sum(0)/areas[:,None]).tolist()}

def fixture_cases():
    points=[[0.,0.,0.],[-1.,0.,1.25],[1.,0.,1.25]]
    normals=[[0.,0.,1.],unit([1.,0.,-1.25]).tolist(),unit([-1.,0.,-1.25]).tolist()]
    mats={str(i):{'tint_linear':[1.,1.,1.],'absorption_code':0,'albedo':[.7,.45,.25] if i==0 else [.6,.7,.8],'roughness':.08 if i==0 else .6,'metallic':0.,'ior':1.5} for i in range(3)}
    model={'schema':1,'factor_normalization':'symmetric_local','patches':[{'position':p,'normal':n,'area':.4,'gray_mean':.7,'material':str(i)} for i,(p,n) in enumerate(zip(points,normals))],
           'materials':mats,'lights':[{'position':[-1.,0.,1.],'radius':6.,'power_rgb':[12.,3.,1.]},{'position':[1.,0.,1.],'radius':6.,'power_rgb':[1.,4.,14.]}],'blockers':[],'triangles':[],'bounces':2}
    matrix=np.array([[0,.22,.22],[.22,0,.05],[.22,.05,0]],float)
    result={}
    def add(name,m=model,mat=matrix,sep=True,**kw):
        pack=sources(m,mat,**kw);result[name]={'model':copy.deepcopy(m),'sources_hex':{k:v.hex() for k,v in pack.items()},'separate':sep,'output':solve(m,pack,sep)}
    add('two_colored_lights');add('legacy_merged',sep=False)
    for side in range(2):
        m=copy.deepcopy(model);m['lights'][1-side]['power_rgb']=[0.,0.,0.];add('left_only' if side==0 else 'right_only',m)
    m=copy.deepcopy(model)
    for light in m['lights']:light['power_rgb']=[0.,0.,0.]
    add('all_off',m)
    m=copy.deepcopy(model);m['bounces']=0;add('direct_only',m)
    m=copy.deepcopy(model);m['materials']['0']['absorption_code']=800;add('absorbing_surface',m)
    m=copy.deepcopy(model);m['materials']['0']['roughness']=1.;add('rough_surface',m)
    m=copy.deepcopy(model);m['materials']['0']['metallic']=1.;add('authored_opaque_metal',m)
    m=copy.deepcopy(model);m['secondary_radii']={'mode':'irradiance','radius_max':6.,'radius_decay':.82,'irradiance_cutoff':.001};add('bounded_radius',m)
    add('occluded_direct',boxes=[[[-.6,-.2,.35],[-.3,.2,.65]]])
    add('explicit_owner_skip',boxes=[[[-.6,-.2,.35],[-.3,.2,.65]]],owners=[0,0xffffffff,0xffffffff])
    m=copy.deepcopy(model);m['lights']=[{'position':[math.sin(i),.2,1.1+math.cos(i)*.2],'radius':6.,'power_rgb':[1+i*.1,.8,.5]} for i in range(8)];add('eight_lights',m)
    m=copy.deepcopy(model)
    for item in m['patches']+m['lights']:item['position']=(np.asarray(item['position'])+[10.,-4.,3.]).tolist()
    add('translated_scene',m)
    # A six-face room uses the same ABI without any brick or three-node recipe.
    p=np.array([[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]],float)*.6
    room=copy.deepcopy(model);room['patches']=[{'position':v.tolist(),'normal':(-unit(v)).tolist(),'area':.8,'gray_mean':.7,'material':str(i%3)} for i,v in enumerate(p)]
    room['lights']=[{'position':[-.2,.1,.1],'radius':6.,'power_rgb':[8.,3.,1.]},{'position':[.2,-.1,-.1],'radius':6.,'power_rgb':[1.,3.,9.]}]
    a=np.zeros((6,6))
    for i in range(6):
        for j in range(6):
            if i!=j:
                d=p[j]-p[i];a[i,j]=.8*max(np.dot(-unit(p[i]),unit(d)),0)*max(np.dot(-unit(p[j]),-unit(d)),0)/(math.pi*np.dot(d,d))
    a/=max(1,a.sum(1).max());add('six_surface_room',room,a)
    return result

def prepare_fixture():
    cases=fixture_cases();out={'schema':'lie-light-field-reference/1','reference':'independent float64 scatter/reduction','cases':cases}
    path=ROOT/'gpu_compute/fixtures/light-field-reference.json';path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(out,indent=2)+'\n')
    return out

if __name__=='__main__':
    fixture=prepare_fixture();a=np.array(fixture['cases']['two_colored_lights']['output']['flux']);b=np.array(fixture['cases']['legacy_merged']['output']['flux'])
    print(json.dumps({'cases':len(fixture['cases']),'legacy_merged_max_error':float(abs(a-b).max())}))
