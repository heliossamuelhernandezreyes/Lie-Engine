"""Acquire independently verifiable REAL photogrammetry geometry (CC BY 4.0).

The source is a scanned *building with visible brick facade*, not a scan of one
individual brick. This is an honest geometric-input reference for evaluating
LIE's geometry-to-samples capture. Distribution follows CC BY 4.0 and keeps
the author's credit and license.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

URL = "https://huggingface.co/datasets/Matt1up/drone-building-scans/resolve/main/flat-roof/model/flat-roof.glb"
SOURCE = "https://github.com/Matt1Up/drone-building-scans-dataset"
AUTHOR = "Matthew Guertin"
LICENSE = "CC BY 4.0"
MAX_DOWNLOAD = 120_000_000


def acquire(directory: Path) -> dict:
    directory.mkdir(parents=True,exist_ok=True)
    request=urllib.request.Request(URL,headers={"User-Agent":"Lie-Engine-research/1.0"})
    content=bytearray()
    with urllib.request.urlopen(request,timeout=120) as stream:
        while True:
            block=stream.read(1024*1024)
            if not block:break
            content.extend(block)
            if len(content)>MAX_DOWNLOAD:raise ValueError("Unexpected GLB size")
    data=bytes(content)
    if len(data)<100 or data[:4]!=b"glTF":
        raise ValueError("Downloaded file is not a GLB 2.0")
    target=directory/"flat-roof-reference.glb"
    target.write_bytes(data)
    report={
        "original_source_url":URL,
        "project":SOURCE,
        "author":AUTHOR,
        "license":LICENSE,
        "commercial_allowed_with_attribution":True,
        "photogrammetry":True,
        "asset_kind":"Entire photographed building with brick facade",
        "NOT_a_single_scanned_brick":True,
        "original_sha256":hashlib.sha256(data).hexdigest(),
        "bytes":len(data)
    }
    (directory/"source-lock.json").write_text(json.dumps(report,indent=2))
    print("LIE34 acquired verified GLB header:",report,flush=True)
    return report


def inspect(directory: Path):
    import numpy as np
    import trimesh

    metadata=acquire(directory) if not (directory/"flat-roof-reference.glb").exists() else json.loads((directory/"source-lock.json").read_text())
    if hashlib.sha256((directory/"flat-roof-reference.glb").read_bytes()).hexdigest()!=metadata["original_sha256"]:
        raise ValueError("GLB SHA drift")
    scene=trimesh.load(str(directory/"flat-roof-reference.glb"),force="scene",process=False)
    meshes=list(scene.geometry.values())
    valid=[m for m in meshes if isinstance(m,trimesh.Trimesh)]
    triangles=sum(len(m.faces) for m in valid)
    vertices=sum(len(m.vertices) for m in valid)
    materials=[type(getattr(m.visual,"material",None)).__name__ for m in valid]
    bounds=scene.bounds
    geometry_bounds=[m.bounds.tolist() for m in valid]
    geometry_extents=[m.extents.tolist() for m in valid]
    graph_nodes=[]
    for node in scene.graph.nodes_geometry:
        pose,name=scene.graph[node]
        graph_nodes.append({"node":node,"mesh":name,"matrix":pose.tolist()})

    data={
        **metadata,"original_meshes":len(valid),
        "original_triangles":int(triangles),
        "original_vertices":int(vertices),
        "world_bounds_m_or_units":[list(map(float,bounds[0])),list(map(float,bounds[1]))] if bounds is not None else None,
        "material_classes":materials[:24],
        "mesh_local_bounds": geometry_bounds[:8],
        "mesh_local_extents": geometry_extents[:8],
        "scene_nodes":graph_nodes[:8],
        "source_glb_rendered_through_LIE":False
    }
    if triangles<1000:raise ValueError("Source scan unexpectedly low detail")
    (directory/"mesh-inspection.json").write_text(json.dumps(data,indent=2))
    print("LIE34 TRUE SCAN INSPECTION",json.dumps(data,indent=2),flush=True)
    return data


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--directory",type=Path,required=True)
    a=ap.parse_args()
    inspect(a.directory)
