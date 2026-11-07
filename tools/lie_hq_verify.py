"""Independent source height-field rays vs actual native LIE RGBA/depth.

The reference shades the consumed geometric-normal GGX model, NOT the full
original tangent-normal PBR material. Report residual detail loss honestly.
"""
import argparse,json,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from scipy.ndimage import binary_erosion
from lie_heightfield_source import read_map,sample_array,linear_albedo

def norm(a):return a/np.maximum(np.linalg.norm(a,axis=-1,keepdims=True),1e-12)
def srgb(a):return np.where(a<=.0031308,a*12.92,1.055*np.maximum(a,0)**(1/2.4)-.055)
def write_image(path,rgb,mask):Image.fromarray(np.uint8(np.clip(np.dstack([rgb,mask]),0,1)*255)).save(path)

def source_reference(src,n=1024):
    d=json.loads((src/'surface.heightfield.json').read_text());crop=np.asarray(d['uv_crop']);dims=np.asarray(d['provider_dimensions_m']);size=(crop[2:]-crop[:2])*dims;grid=d['grid_vertices_per_axis']
    h=read_map(src/'Displacement.png','Displacement');u,v=np.meshgrid(np.linspace(crop[0],crop[2],grid),np.linspace(crop[1],crop[3],grid))
    z=(sample_array(h,np.column_stack([u.ravel(),v.ravel()]))-d['displacement_midlevel'])*d['displacement_scale_m'];z=z.reshape(grid,grid)
    def surface(x,y):
        qx=np.clip((x/size[0]+.5)*(grid-1),0,grid-1-1e-7);qy=np.clip((y/size[1]+.5)*(grid-1),0,grid-1-1e-7);ix=qx.astype(int);iy=qy.astype(int);fx=qx-ix;fy=qy-iy
        a=z[iy,ix];b=z[iy,ix+1];c=z[iy+1,ix];e=z[iy+1,ix+1];tri=fy<=fx
        value=np.where(tri,a*(1-fx)+b*(fx-fy)+e*fy,a*(1-fy)+e*fx+c*(fy-fx))
        dx=np.where(tri,b-a,e-c)*(grid-1)/size[0];dy=np.where(tri,e-b,c-a)*(grid-1)/size[1]
        return value,norm(np.stack([-dx,-dy,np.ones_like(dx)],axis=-1))
    extent=max(size);distance=extent*1.8;tangent=math.tan(math.radians(21));x,y=np.meshgrid(((np.arange(n)+.5)/n*2-1)*tangent,(1-(np.arange(n)+.5)/n*2)*tangent)
    low=np.full((n,n),distance-z.max()-.001);high=np.full((n,n),distance-z.min()+.001)
    for _ in range(24):
        t=(low+high)/2;value,_=surface(x*t,y*t);above=distance-t>value;low=np.where(above,t,low);high=np.where(above,high,t)
    t=(low+high)/2;px=x*t;py=y*t;pz=distance-t;_,normal=surface(px,py);mask=(abs(px)<size[0]/2)&(abs(py)<size[1]/2)
    uv=np.stack([px/dims[0]+(crop[0]+crop[2])/2,py/dims[1]+(crop[1]+crop[3])/2],axis=-1).reshape(-1,2)
    color=np.clip(sample_array(linear_albedo(read_map(src/'Diffuse.exr','Diffuse'),d['diffuse_encoding']),uv),0,1).reshape(n,n,3)
    rough=np.clip(sample_array(read_map(src/'Rough.exr','Rough'),uv),.2,.95).reshape(n,n)
    point=np.stack([px,py,pz],axis=-1);eye=np.array([0,0,distance]);r=distance*.7;angle=math.radians(-35);light=np.array([math.sin(angle)*r,r*.9,math.cos(angle)*r]);delta=light-point;distance2=(delta**2).sum(-1);l=norm(delta);v=norm(eye-point);half=norm(v+l)
    nl=np.maximum((normal*l).sum(-1),0);nv=np.maximum((normal*v).sum(-1),1e-5);nh=np.maximum((normal*half).sum(-1),0);vh=np.maximum((v*half).sum(-1),0);F=.025+.975*(1-vh)**5;a2=rough**4;denom=nh**2*(a2-1)+1;D=a2/(np.pi*denom**2)
    def lam(c):return .5*(np.sqrt(1+a2*np.maximum(1-c*c,0)/np.maximum(c*c,1e-8))-1)
    G=1/(1+lam(nv)+lam(nl));li=np.array([1,.96,.91])*(55*r*r/(4*np.pi*distance2))[...,None]
    diffuse=(1-F)[...,None]*(li*nl[...,None]/np.pi+np.array([.27,.30,.36])*.12);spec=li*(F*D*G/(4*nv)*(nl>0))[...,None]
    linear=np.maximum((color*diffuse+spec)*1.6,0);rgb=srgb(linear/(1+linear))
    return rgb,mask,t,normal,color

def verify(sources,stage,out):
    out.mkdir(parents=True,exist_ok=True);native=json.loads((stage/'hq-native.json').read_text());reports={};names=['concrete_layers','wood_table_worn','rock_boulder_dry','grey_plaster']
    for name in names:
        ref,mask,depth,normal,albedo=source_reference(sources/name);n=len(mask)
        raw=np.fromfile(stage/(name+'-front.rgba32f'),dtype='<f4').reshape(n,n,4);actual_depth=np.fromfile(stage/(name+'-front.depth32f'),dtype='<f4').reshape(n*2,n*2)[1::2,1::2]
        interior=binary_erosion(mask,iterations=8);covered=raw[:,:,3]>.99;valid=interior&covered&np.isfinite(actual_depth);coverage=float(covered[interior].mean());mse=float(np.mean((raw[:,:,:3][valid]-ref[valid])**2));rmse=float(np.sqrt(np.mean((actual_depth[valid]-depth[valid])**2)))
        report={'source_model':'2M-triangle geometric relief + original linear albedo/roughness; optical normal map excluded','interior_coverage':coverage,'rgb_psnr_db':float(-10*np.log10(max(mse,1e-15))),'depth_rmse_m':rmse,'native_device':native['cases'][name]['device'],'quality_claim':'source high-resolution verified; retained detail limited by capture density and missing optical normal channel','passed':coverage>=.995 and rmse<.003 and mse<.01}
        reports[name]=report
        write_image(out/(name+'-reference.png'),ref,mask);write_image(out/(name+'-albedo.png'),srgb(albedo),mask);write_image(out/(name+'-geometric-normal.png'),normal*.5+.5,mask)
        print(name,json.dumps(report),flush=True)
    result={'schema':'lie-hq-native-source-comparison/1','physical_android_tested':False,'full_original_optical_normal_model_compared':False,'hero_quality_certification':False,'passed':not native['failed'] and all(r['passed'] for r in reports.values()),'materials':reports}
    (out/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',23);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18);canvas=Image.new('RGB',(1680,1920),(23,28,36));draw=ImageDraw.Draw(canvas)
    draw.text((40,25),'LIE · BANCO DE MATERIALES FOTOGRÁFICOS 8K',font=font,fill='white');draw.text((40,65),'Fuente conservada + relieve real · Capturas nativas a 1024 px · Powered by Poly Haven',font=small,fill='#bdc7d1')
    for row,name in enumerate(names):
        y=115+row*445;draw.text((40,y),name.replace('_',' ').title(),font=font,fill='white')
        for col,(path,label) in enumerate([(out/(name+'-reference.png'),'Referencia del modelo capturado'),(stage/(name+'-front.png'),'Reconstrucción LIE · vista frontal'),(stage/(name+'-case-'+str(row*7)+'.png'),'LIE · vista oblicua')]):
            # Native case keys increment with the extra per-material report row.
            if not path.exists():
                candidates=sorted(stage.glob(name+'-case-*.png'));path=candidates[0]
            im=Image.open(path).convert('RGBA');bg=Image.new('RGBA',im.size,(45,51,60,255));bg.alpha_composite(im);im=bg.convert('RGB').resize((370,370),Image.Resampling.LANCZOS);x=40+col*550;canvas.paste(im,(x,y+35));draw.text((x,y+410),label,font=small,fill='#c7d0db')
    canvas.save(out/'LIE_Materiales_HQ_v4.png')
    if not result['passed']:raise SystemExit('HQ source comparison failed; preserve evidence')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--stage',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();verify(a.sources,a.stage,a.output)
