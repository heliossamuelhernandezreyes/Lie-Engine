"""Inspect KHR_draco_mesh_compression bytes from a genuine CC BY GLB.
An empty trimesh scene is not evidence of missing geometry when Draco is used.
"""
from __future__ import annotations
import json,struct
from pathlib import Path
import numpy as np


def probe(path:Path):
    import DracoPy
    data=path.read_bytes()
    length,typ=struct.unpack_from("<II",data,12)
    if typ!=0x4e4f534a:raise ValueError("Unexpected GLB JSON chunk")
    doc=json.loads(data[20:20+length].decode().strip())
    off=20+length
    binary_length,typ=struct.unpack_from("<II",data,off)
    if typ!=0x004e4942:raise ValueError("Expected GLB BIN chunk")
    binary=data[off+8:off+8+binary_length]
    for i,mesh in enumerate(doc["meshes"]):
        for j,primitive in enumerate(mesh["primitives"]):
            ext=primitive["extensions"]["KHR_draco_mesh_compression"]
            view=doc["bufferViews"][ext["bufferView"]]
            compressed=binary[view.get("byteOffset",0):view.get("byteOffset",0)+view["byteLength"]]
            decoded=DracoPy.decode(compressed)
            print("Draco decoded mesh",i,j,
                  "vertices",len(decoded.points),"triangles",len(decoded.faces),
                  "bbox",np.min(decoded.points,axis=0).tolist(),np.max(decoded.points,axis=0).tolist(),
                  "attr",ext["attributes"],
                  "normals",None if decoded.normals is None else decoded.normals.shape,
                  "uvs",None if decoded.tex_coord is None else decoded.tex_coord.shape,
                  "colors",None if decoded.colors is None else decoded.colors.shape,
                  flush=True)
            if not len(decoded.faces) or np.max(decoded.points)-np.min(decoded.points)<1e-6:
                raise ValueError("Draco decoded degenerate vertices")


if __name__=="__main__":
    import argparse
    ap=argparse.ArgumentParser();ap.add_argument("glb",type=Path)
    args=ap.parse_args()
    probe(args.glb)
