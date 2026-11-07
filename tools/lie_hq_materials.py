"""Acquire pinned original 8K maps; compile photographic relief with shared LIE backend.

Independent immutable banks keep the original quality without exceeding the
64 MiB resident-bank contract. No full-object or seamless-crop claims.
"""
import argparse,hashlib,json,urllib.request,shutil
from pathlib import Path
import numpy as np
from PIL import Image
from lie_asset_capture import capture
from lie_heightfield_source import file_sha,read_map
from lie_asset_sets import compile_set

ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'gpu_compute/assets/hq_materials/sources.lock.json'
COUNTS=(512000,128000,32000)

def write(path,data):path.write_text(json.dumps(data,indent=2)+'\n')

def verify_color_encoding(src,encoding):
    raw=read_map(src/'Diffuse.exr','Diffuse')[4::8,4::8].astype(np.float32)
    with Image.open(src/'ColorReference.jpg') as im:ref=np.asarray(im)[4::8,4::8].astype(np.float32)/255.
    converted=np.where(raw<=.0031308,raw*12.92,1.055*np.maximum(raw,0)**(1/2.4)-.055)
    raw_mae=float(np.mean(abs(raw-ref)));converted_mae=float(np.mean(abs(converted-ref)))
    claimed,alternate=(raw_mae,converted_mae) if encoding=='srgb' else (converted_mae,raw_mae)
    if claimed>=.03 or claimed*2>=alternate:raise ValueError('diffuse_encoding_does_not_match_provider_sRGB_reference')
    return {'encoding':encoding,'reference':'provider original 8K JPEG; sRGB assigned in provider Blender material','encoded_EXR_vs_JPEG_mae':raw_mae,'linear_EXR_hypothesis_to_sRGB_vs_JPEG_mae':converted_mae,'passed':True}

def write_sets(bank,name,meta):
    leaf=lambda lod:{'id':'surface','asset':name,'lod':lod}
    document={'schema':'lie-asset-sets/1','bank_sha256':meta['sha256'],
              'assets':{name:{'master':name,'role':'photographic_surface','scale_policy':'rigid'}},
              'sets':{'panel':{'nodes':[leaf(0)]},'near_panel':{'nodes':[leaf(1)]},'quartet':{'nodes':[]}}}
    for i in range(4):
        angle=-i*np.pi/2;c=float(np.cos(angle));s=float(np.sin(angle));R=np.array([[c,-s,0],[s,c,0],[0,0,1]])
        document['sets']['quartet']['nodes'].append({'id':'panel-'+str(i),'set':'near_panel','origin':[(i%2-.5)*.34,(i//2-.5)*.34,0],'basis_columns':R.T.tolist()})
    write(bank/'sets.json',document)
    for key in ('panel','quartet'):
        write(bank/(key+'.json'),{'bank_sha256':meta['sha256'],'instances':compile_set(document,key,meta),'bounds_m':[.32,.32,meta['source_bbox_m'][2]] if key=='panel' else [.66,.66,meta['source_bbox_m'][2]]})

def acquire(root,lock):
    for name,item in lock['materials'].items():
        target=root/name;target.mkdir(parents=True,exist_ok=True)
        for kind,m in item['maps'].items():
            dst=target/(kind+'.'+m['url'].rsplit('.',1)[1])
            if not dst.exists():
                part=dst.with_suffix(dst.suffix+'.part')
                req=urllib.request.Request(m['url'],headers={'User-Agent':'LIE HQ materials; Powered by Poly Haven'})
                with urllib.request.urlopen(req,timeout=180) as r,part.open('wb') as f:shutil.copyfileobj(r,f)
                part.rename(dst)
            if dst.stat().st_size!=m['size'] or file_sha(dst)!=m['sha256']:raise ValueError('pinned_source_hash: '+str(dst))
            print('SOURCE VERIFIED',name,kind,flush=True)

def prepare(sources,output,lock,only=None):
    output.mkdir(parents=True,exist_ok=True)
    for name,item in lock['materials'].items():
        if only and name!=only:continue
        src=sources/name;src.mkdir(parents=True,exist_ok=True);bank=output/name
        declaration={k:item[k] for k in ('provider_dimensions_m','displacement_scale_m','displacement_midlevel','uv_crop','grid_vertices_per_axis','diffuse_encoding')}
        declaration.update(schema='lie-photographic-heightfield/1',normal_policy=lock['normal_policy'],
                           source_resolution=lock['source_resolution'],
                           maps={k:{'path':k+'.'+v['url'].rsplit('.',1)[1],'sha256':v['sha256']} for k,v in item['maps'].items() if k!='source'})
        source=src/'surface.heightfield.json';write(source,declaration)
        provenance={k:item[k] for k in ('title','author','source_url')}
        provenance.update(license=lock['license'],capture_kind='photographic PBR surface on authored height-field, not a complete-object scan',expected_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        write(src/'provenance.json',provenance)
        profile={'master':name,'source_to_lie':np.eye(3).tolist(),'meters_per_source_unit':1.,'source_pivot':[0,0,0],'material_zone':10,'source_material_policy':'declared_opaque_override','optical_material':{'metallic':0.,'transmission':0.,'ior':1.5,'roughness_origin':'source_map'},'clip_support_to_source_aabb':True}
        write(src/'asset-profile.json',profile)
        encoding_report=verify_color_encoding(src,item['diffuse_encoding'])
        meta=capture(source,src/'provenance.json',bank,counts=COUNTS,asset_profile=profile)
        write(bank/'color-encoding.json',encoding_report)
        meta.update(material_source=item,credit=lock['credit'],source_resolution=lock['source_resolution'],
                    tile_size_m=[.32,.32],crop_is_seamless=False,full_source_maps_retained=True,
                    geometry_role='open surface patch; no side or back invented',
                    displacement_scale_origin='provider Blender node, not measured/certified depth',
                    material_range_policy='original EXR retained, bounded opaque RGB and roughness derivative clamped to 0..1')
        write(bank/'catalog.json',meta)
        write(bank/'source-links.json',{'source':str(source.relative_to(sources.parent)),'sha256':provenance['expected_sha256'],'maps':declaration['maps']})
        write_sets(bank,name,meta)
        print('BANK READY',name,meta['bytes'],flush=True)
    write(output/'manifest.json',lock)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--acquire',action='store_true');p.add_argument('--only');a=p.parse_args();lock=json.loads(LOCK.read_text())
    if a.acquire:acquire(a.sources,lock)
    prepare(a.sources,a.output,lock,a.only)
