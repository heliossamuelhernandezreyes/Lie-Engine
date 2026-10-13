"""Synthetic irregular textured GLB for regression only — NEVER a photo scan."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
import trimesh


def build(directory: Path) -> tuple[Path, Path]:
    directory.mkdir(parents=True, exist_ok=True)
    mesh = trimesh.creation.box(extents=(.2032, .055, .093))
    for _ in range(4):
        mesh = mesh.subdivide()
    verts = mesh.vertices.copy()
    # Genuine 3D geometry in fixture, but entirely synthetic. Boundary
    # irregularity forces importer to preserve observed surface coordinates.
    x, y, z = verts.T
    ripple = .0014 * np.sin(203*x + 82*z + 41*y) + .0006*np.cos(515*z-49*y)
    verts[:,1] += ripple * np.sign(y)
    verts[:,2] -= .0008 * np.exp(-((x+.101)/.018)**2) * np.sign(z)
    mesh.vertices = verts
    uv = np.column_stack(((x/.2032+.5)*2.3, (z/.093+.5)*1.8)).astype(np.float32)
    image = np.zeros((64,64,3), dtype=np.uint8)
    X,Y = np.meshgrid(np.arange(64),np.arange(64))
    image[:,:,0] = 110+(X*9+Y*7)%75
    image[:,:,1] = 37+(X*3+Y*5)%38
    image[:,:,2] = 27+(X*7+Y*2)%24
    material = trimesh.visual.material.PBRMaterial(
        baseColorTexture=Image.fromarray(image), roughnessFactor=.87, metallicFactor=0.)
    mesh.visual = trimesh.visual.TextureVisuals(uv=uv, material=material)
    glb = directory / "SYNTHETIC_NOT_PHOTOGRAMMETRY.glb"
    glb.write_bytes(mesh.export(file_type="glb"))
    provenance = directory / "provenance.json"
    provenance.write_text(json.dumps({
        "title":"LIE deterministic synthetic brick test — NOT A SCAN",
        "author":"LIE test fixture generator",
        "license":"CC0 1.0",
        "source_url":"https://github.com/heliossamuelhernandezreyes/Lie-Engine",
        "capture_kind":"synthetic geometry; not photogrammetry",
        "expected_sha256":hashlib.sha256(glb.read_bytes()).hexdigest()
    },indent=2),encoding="utf-8")
    return glb, provenance


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory",type=Path,required=True)
    args=parser.parse_args()
    model, provenance=build(args.directory)
    print(json.dumps({"fixture_glb":str(model),"provenance":str(provenance),"size":model.stat().st_size}))
