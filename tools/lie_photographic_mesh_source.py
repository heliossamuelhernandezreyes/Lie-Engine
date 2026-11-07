"""Authored 3D source with photographed PBR; not a complete-object scan."""
import json
from pathlib import Path
import numpy as np
import trimesh
from lie_heightfield_source import file_sha,read_map,linear_albedo
def load_photomesh(source):
    d=json.loads(Path(source).read_text());root=Path(source).parent.resolve();paths={}
    if d.get('schema')!='lie-photographic-mesh/1':raise ValueError('photomesh_schema')
    for key,spec in {'mesh':d['mesh'],**d['maps']}.items():
        path=(root/spec['path']).resolve()
        if not path.is_relative_to(root) or file_sha(path)!=spec['sha256']:raise ValueError('photomesh_source_hash_or_path')
        paths[key]=path
    with np.load(paths['mesh'],allow_pickle=False) as data:
        mesh=trimesh.Trimesh(vertices=data['vertices'],faces=data['faces'],process=False);mesh.visual=trimesh.visual.TextureVisuals(uv=data['uv'])
    if not np.isfinite(mesh.vertices).all() or mesh.visual.uv.shape!=(len(mesh.vertices),2) or not np.isfinite(mesh.visual.uv).all():raise ValueError('photomesh_geometry')
    mesh.metadata['lie_photographic_linear_maps']={'Diffuse':linear_albedo(read_map(paths['Diffuse'],'Diffuse'),d['diffuse_encoding']),'Rough':read_map(paths['Rough'],'Rough')}
    mesh.metadata['lie_optical_normal_map']=read_map(paths['nor_gl'],'nor_gl');mesh.metadata['lie_photographic_mesh_declaration']=d
    return [mesh]
