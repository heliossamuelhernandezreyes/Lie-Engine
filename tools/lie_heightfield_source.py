"""Explicit photographic surface source for the common opaque capture compiler.

This is a surface, never a whole-object scan. XY comes from provider metadata;
Z is the provider's Blender displacement setup, not certified metrology.
The original tangent normal map is retained but NOT substituted for geometry.
"""
import hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image
import trimesh

def file_sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def sample_array(pixels,uv):
    """Bilinear glTF UV convention, pixel centres, repeat addressing."""
    h,w=pixels.shape[:2];q=np.mod(uv,1.);x=q[:,0]*w-.5;y=(1-q[:,1])*h-.5
    ix=np.floor(x).astype(np.int64);iy=np.floor(y).astype(np.int64)
    dx=x-ix;dy=y-iy
    if pixels.ndim==3:dx=dx[:,None];dy=dy[:,None]
    return ((pixels[iy%h,ix%w]*(1-dx)+pixels[iy%h,(ix+1)%w]*dx)*(1-dy)+
            (pixels[(iy+1)%h,ix%w]*(1-dx)+pixels[(iy+1)%h,(ix+1)%w]*dx)*dy).astype(np.float32)

def read_map(path,kind):
    if path.suffix=='.exr':
        import OpenEXR
        f=OpenEXR.File(str(path));channels=f.channels()
        a=channels['RGB'].pixels if 'RGB' in channels else channels[next(iter(channels))].pixels
        if kind!='Diffuse' and a.ndim==3:a=a[:,:,0]
    else:
        if kind=='Displacement':
            with path.open('rb') as f:header=f.read(26)
            if header[:8]!=b'\x89PNG\r\n\x1a\n' or header[24]!=16:raise ValueError('height_requires_original_16bit_scalar')
            # Pillow converts 16-bit RGB PNG to 8-bit RGB. The stone height is
            # stored as RGB16; read it without that silent precision loss.
            if header[25]==2:
                import OpenImageIO as oiio
                inp=oiio.ImageInput.open(str(path))
                if inp is None:raise ValueError('height_image_read')
                try:a=inp.read_image(format=oiio.FLOAT)
                finally:inp.close()
                if a.ndim!=3 or a.shape[2]!=3 or np.max(abs(a[:,:,0]-a[:,:,1]))>1e-6 or np.max(abs(a[:,:,0]-a[:,:,2]))>1e-6:raise ValueError('height_rgb_is_not_scalar')
                a=a[:,:,0]
            else:
                with Image.open(path) as im:a=np.asarray(im).astype(np.float32)/65535.
                if a.ndim!=2:raise ValueError('height_requires_original_16bit_scalar')
        else:raise ValueError('photographic_color_requires_EXR_with_declared_encoding')
    # Provider EXR DWAA compression can overshoot [0,1] very slightly. Preserve
    # the original file and clamp the bounded opaque derivative explicitly.
    if not np.isfinite(a).all() or a.min()<-.02 or a.max()>1.02:raise ValueError('source_map_out_of_range: '+str(path)+' '+str((a.min(),a.max())))
    return a

def linear_albedo(pixels,encoding):
    if encoding not in ('linear','srgb'):raise ValueError('explicit_diffuse_encoding_required')
    if encoding=='linear':return pixels
    # Decode each texel before UV filtering. EXR is a container, not a
    # reliable declaration of color encoding for these provider files.
    result=np.empty(pixels.shape,dtype=np.float32)
    for row in range(0,len(pixels),128):
        p=np.clip(pixels[row:row+128].astype(np.float32),0,1)
        result[row:row+128]=np.where(p<=.04045,p/12.92,((p+.055)/1.055)**2.4)
    return result

def load_heightfield(source):
    d=json.loads(Path(source).read_text());root=Path(source).parent
    if d.get('schema')!='lie-photographic-heightfield/1' or d.get('normal_policy')!='retain_original_not_consumed_by_80B':raise ValueError('heightfield_policy')
    maps={}
    for kind,info in d['maps'].items():
        path=(root/info['path']).resolve()
        if not path.is_relative_to(root.resolve()):raise ValueError('heightfield_path_escape')
        if file_sha(path)!=info['sha256']:raise ValueError('heightfield_source_map_hash')
        if kind in ('Diffuse','Rough','Displacement'):maps[kind]=read_map(path,kind)
    if set(maps)!={'Diffuse','Rough','Displacement'}:raise ValueError('heightfield_missing_maps')
    if 'source_resolution' in d and any(list(a.shape[:2])!=d['source_resolution'][::-1] for a in maps.values()):raise ValueError('heightfield_source_resolution')
    maps['Diffuse']=linear_albedo(maps['Diffuse'],d.get('diffuse_encoding'))
    dims=np.asarray(d['provider_dimensions_m'],float);crop=np.asarray(d['uv_crop'],float);n=d['grid_vertices_per_axis']
    if dims.shape!=(2,) or (dims<=0).any() or crop.shape!=(4,) or not np.isfinite([*dims,*crop]).all() or not (0<=crop[0]<crop[2]<=1 and 0<=crop[1]<crop[3]<=1) or type(n) is not int or not 3<=n<=2049:raise ValueError('heightfield_geometry_declaration')
    scale=float(d['displacement_scale_m']);mid=float(d['displacement_midlevel'])
    if not np.isfinite([scale,mid]).all() or not 0<scale<=.5 or not 0<=mid<=1:raise ValueError('heightfield_displacement')
    # Proper X-right / Y-up / Z-front surface frame. No automatic PCA or mirroring.
    u,v=np.meshgrid(np.linspace(crop[0],crop[2],n),np.linspace(crop[1],crop[3],n));uv=np.stack([u.ravel(),v.ravel()],axis=1)
    z=(sample_array(maps['Displacement'],uv)-mid)*scale
    vertices=np.column_stack([(uv[:,0]-(crop[0]+crop[2])/2)*dims[0],(uv[:,1]-(crop[1]+crop[3])/2)*dims[1],z])
    i=np.arange(n*n).reshape(n,n);a=i[:-1,:-1].ravel();b=a+1;c=a+n;e=c+1
    faces=np.concatenate([np.column_stack([a,b,e]),np.column_stack([a,e,c])])
    mesh=trimesh.Trimesh(vertices=vertices,faces=faces,process=False)
    mesh.visual=trimesh.visual.TextureVisuals(uv=uv)
    mesh.metadata['lie_photographic_linear_maps']=maps
    mesh.metadata['lie_heightfield_declaration']=d
    return [mesh]

def sample_material(mesh,uv):
    maps=mesh.metadata['lie_photographic_linear_maps']
    return np.clip(sample_array(maps['Diffuse'],uv),0,1),np.clip(sample_array(maps['Rough'],uv),0,1)
