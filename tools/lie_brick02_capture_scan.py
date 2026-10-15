"""LIE-BRICK-02: capture an authorized *whole-object* textured scan as 80-byte LIE samples.

The mesh is an OFFLINE capture source, never rasterized by the LIE runtime.
This is deliberately NOT a downloader for Sketchfab and NOT a license verifier.
Use an authorized unpacked .glb/.gltf/.obj with its required adjacent textures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
import trimesh
from lie_gltf_vertex_color import load_colored_glb, read_glb
from lie_asset_contract import proper_rotation,inspect_bank,optical_profile

STRIDE = 80
MAX_SAMPLES = 750_000
MAX_BANK_BYTES = 64 * 1024 * 1024
DEFAULT_COUNTS = (220_000, 52_000, 9_000)
SUPPORTED = {".glb", ".gltf", ".obj"}
REQUIRED_PROVENANCE = ("title", "author", "license", "source_url", "capture_kind")


def linear_srgb(rgb: np.ndarray) -> np.ndarray:
    return np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)


def normalized(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def uv_sample(image: Image.Image, uv: np.ndarray) -> np.ndarray:
    """Bilinear wrapped glTF UV sample, flip V for image rows."""
    pixels = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.
    height, width = pixels.shape[:2]
    frac = np.mod(uv, 1.)
    x = frac[:, 0] * width - .5
    y = (1. - frac[:, 1]) * height - .5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    dx = (x - x0)[:, None]
    dy = (y - y0)[:, None]
    a = pixels[y0 % height, x0 % width]
    b = pixels[y0 % height, (x0 + 1) % width]
    c = pixels[(y0 + 1) % height, x0 % width]
    d = pixels[(y0 + 1) % height, (x0 + 1) % width]
    return ((a * (1 - dx) + b * dx) * (1 - dy) +
            (c * (1 - dx) + d * dx) * dy).astype(np.float32)


def material_maps(mesh: trimesh.Trimesh) -> tuple[Image.Image | None, Image.Image | None, float]:
    if "lie_vertex_colors_linear" in mesh.metadata:
        return None, None, float(mesh.metadata["lie_material_roughness"])
    visual = mesh.visual
    material = getattr(visual, "material", None)
    if material is None:
        return None, None, .85
    base = getattr(material, "baseColorTexture", None)
    if base is None:
        base = getattr(material, "image", None)
    rough_map = getattr(material, "metallicRoughnessTexture", None)
    rough_factor = getattr(material, "roughnessFactor", None)
    return base, rough_map, float(.85 if rough_factor is None else rough_factor)


def load_source(source: Path) -> list[trimesh.Trimesh]:
    if not source.is_file() or source.suffix.lower() not in SUPPORTED:
        raise ValueError("Input must be an existing .glb, .gltf or .obj file (extract any downloaded ZIP first)")
    try:
        if source.suffix.lower() == ".glb":
            doc, _ = read_glb(source)
            primitives = [p for mesh in doc.get("meshes",[]) for p in mesh.get("primitives",[])]
            if primitives and all("COLOR_0" in p.get("attributes",{}) for p in primitives) and not doc.get("images"):
                # Original Stratford scan uses 500K source triangles, COLOR_0
                # linear vertex colors, NO UVs and NO photographic atlas. Reuse
                # actual vertex colors, never invent or retexture the object.
                meshes = load_colored_glb(source)
            else:
                scene = trimesh.load(str(source), force="scene", process=False)
                meshes = [m for m in scene.dump() if isinstance(m, trimesh.Trimesh)
                          and len(m.faces) and len(m.vertices)]
        else:
            scene = trimesh.load(str(source), force="scene", process=False)
            meshes = [m for m in scene.dump() if isinstance(m, trimesh.Trimesh)
                      and len(m.faces) and len(m.vertices)]
    except Exception as error:
        raise ValueError(f"Unable to read genuine mesh geometry: {error}. "
                         "Draco-compressed glTF may need authorized Blender/Draco decoding first.") from error
    if not meshes:
        raise ValueError("Missing physical source triangles")
    for mesh in meshes:
        if not np.isfinite(mesh.vertices).all():
            raise ValueError("Non-finite scanned vertices")
        if len(mesh.faces) < 1 or float(mesh.area) <= 1e-12:
            raise ValueError("Source has degenerate or zero-area triangles")
        if "lie_vertex_colors_linear" in mesh.metadata:
            color = np.asarray(mesh.metadata["lie_vertex_colors_linear"])
            if color.shape != (len(mesh.vertices),3) or not np.isfinite(color).all():
                raise ValueError("Source COLOR_0 missing or inconsistent")
            continue
        if mesh.visual.kind != "texture":
            raise ValueError("Source lacks texture UVs and vertex COLOR_0; no invented color")
        uv = np.asarray(mesh.visual.uv)
        if uv.shape != (len(mesh.vertices), 2) or not np.isfinite(uv).all():
            raise ValueError("Missing or invalid source UVs")
        texture, _, _ = material_maps(mesh)
        if texture is None or not isinstance(texture, Image.Image):
            raise ValueError("Missing actual photographic texture. Check OBJ/MTL image paths or GLB texture embedding.")
    return meshes


def frame_for_brick(meshes: list[trimesh.Trimesh], length_m: float) -> tuple[np.ndarray, float, np.ndarray]:
    """Canonical X=long axis, Y=thin axis, Z=other; don't rewrite the shape."""
    if not (.05 <= length_m <= 2.):
        raise ValueError("Measured target length must be within 0.05..2 m")
    limits = np.stack([np.vstack([m.vertices.min(axis=0), m.vertices.max(axis=0)]) for m in meshes])
    low = np.min(limits[:, 0], axis=0)
    high = np.max(limits[:, 1], axis=0)
    spans = high - low
    if not np.isfinite(spans).all() or np.min(spans) < 1e-7:
        raise ValueError("The 3D source must occupy a real volume, not a flat wall")
    order = np.argsort(spans)
    # Longest to X, thinnest to Y, remaining to Z
    perm = np.array([int(order[2]), int(order[0]), int(order[1])])
    ordered = spans[perm]
    if ordered[1] / ordered[0] < .08:
        raise ValueError("Input is excessively flat for a complete brick")
    scale = length_m / ordered[0]
    return perm, float(scale), (low + high) / 2


def _sample_mesh(mesh: trimesh.Trimesh, count: int, rng: np.random.Generator,
                 perm: np.ndarray, scale: float, center: np.ndarray,
                 radius: float, basis=None) -> np.ndarray:
    triangles = mesh.faces
    areas = np.asarray(mesh.area_faces, dtype=np.float64)
    positive = np.where(areas > 1e-14, areas, 0.)
    total = float(positive.sum())
    if total <= 1e-12:
        raise ValueError("Degenerate triangle areas")
    cumulative = np.cumsum(positive)
    chosen = np.searchsorted(cumulative, rng.random(count) * cumulative[-1], side="right")
    chosen = np.minimum(chosen, len(triangles) - 1)
    face = triangles[chosen]
    a = np.sqrt(rng.random(count))
    b = rng.random(count)
    weights = np.stack([1 - a, a * (1 - b), a * b], axis=-1).astype(np.float32)
    position = np.einsum("ijk,ij->ik", np.asarray(mesh.vertices)[face], weights)
    # Preserve scanned silhouette and face microtopology; face normals resist
    # over-smoothing an actual photographed broken edge.
    fn = np.asarray(mesh.face_normals)[chosen]
    vn = np.einsum("ijk,ij->ik", np.asarray(mesh.vertex_normals)[face], weights)
    nr = normalized(.70 * fn + .30 * vn)
    colored = "lie_vertex_colors_linear" in mesh.metadata
    uv = None if colored else np.einsum("ijk,ij->ik", np.asarray(mesh.visual.uv)[face], weights)

    diffuse, mr, factor = material_maps(mesh)
    rgb = (np.einsum("ijk,ij->ik", np.asarray(mesh.metadata["lie_vertex_colors_linear"])[face], weights)
           if colored else uv_sample(diffuse, uv))
    material = getattr(mesh.visual, "material", None)
    base_factor = getattr(material, "baseColorFactor", None)
    if base_factor is not None:
        rgb *= (np.asarray(base_factor[:3], dtype=np.float32) / 255. if
                max(base_factor[:3]) > 1 else np.asarray(base_factor[:3], dtype=np.float32))
    # glTF COLOR_0 already stores LINEAR radiometric vertex color.
    # UV photographic color textures are sRGB and need linear conversion.
    rgb = np.clip(rgb, 0, 1) if colored else linear_srgb(np.clip(rgb, 0, 1))
    rough = (np.clip(uv_sample(mr, uv)[:, 1] * factor, .18, .98) if (mr is not None and uv is not None)
             else np.full(count, np.clip(factor, .18, .98), dtype=np.float32))
    world = ((position - center)[:, perm] * scale).astype(np.float32)
    normals = normalized(nr[:, perm]).astype(np.float32)
    if basis is not None:
        world=((position-center)@basis.T*scale).astype(np.float32)
        normals=normalized(nr@basis.T).astype(np.float32)
    out = np.zeros((count, 20), dtype="<f4")
    out[:, :3] = world
    out[:, 3] = radius
    out[:, 4:7] = normals
    out[:, 7] = 1.
    out[:, 8] = 3.  # clay material code
    out[:, 10] = rough
    out[:, 12:15] = rgb
    out[:, 15] = 1.
    # Dominant-plane bounded support: independent of spatial envelope.
    dominant = np.argmax(np.abs(normals), axis=1)
    for axis, (u, v) in enumerate(((2, 1), (0, 2), (0, 1))):
        chosen_axis = dominant == axis
        coords = world[chosen_axis][:, [u, v]]
        out[chosen_axis, 16:18] = coords - 2.3 * radius
        out[chosen_axis, 18:20] = coords + 2.3 * radius
    if not np.isfinite(out).all():
        raise ValueError("Non-finite sampled brick")
    return out


def capture(source: Path, provenance: Path, output: Path, length_m: float = .2032,
            counts: tuple[int, int, int] = DEFAULT_COUNTS, seed: int = 2102, asset_profile=None) -> dict:
    if len(counts) != 3 or any(x < 100 for x in counts) or sum(counts) > MAX_SAMPLES:
        raise ValueError("Require 3 LOD levels of >=100 samples; max total 750K")
    identity = json.loads(provenance.read_text(encoding="utf-8"))
    if any(not isinstance(identity.get(k), str) or not identity[k].strip()
           for k in REQUIRED_PROVENANCE):
        raise ValueError("The source title, author, license, URL and capture_kind are mandatory")
    if identity["license"] not in ("CC0 1.0", "CC BY 4.0"):
        raise ValueError("License not yet reviewed for redistribution; fail closed")
    source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    expected = identity.get("expected_sha256")
    if expected and expected.lower() != source_sha:
        raise ValueError("Source SHA-256 does not match provenance lock")
    if asset_profile is not None:
        policy=asset_profile.get('source_material_policy','preserve_source')
        if source.suffix.lower()=='.obj' and policy!='declared_opaque_override':raise ValueError('asset_obj_requires_declared_material_override')
        doc=read_glb(source)[0] if source.suffix.lower()=='.glb' else json.loads(source.read_text()) if source.suffix.lower()=='.gltf' else {}
        if policy not in ('preserve_source','declared_opaque_override'):raise ValueError('asset_source_material_policy')
        for material in doc.get('materials',[]):
            pbr=material.get('pbrMetallicRoughness',{})
            unsupported=(float(pbr.get('metallicFactor',1))!=0 or material.get('alphaMode','OPAQUE')!='OPAQUE' or material.get('normalTexture') is not None or float(material.get('extensions',{}).get('KHR_materials_transmission',{}).get('transmissionFactor',0))>0)
            unsupported |= bool(material.get('extensions')) or any(float(x)!=0 for x in material.get('emissiveFactor',[0,0,0])) or material.get('occlusionTexture') is not None
            for texture in ('baseColorTexture','metallicRoughnessTexture'):
                info=pbr.get(texture,{})
                unsupported |= bool(info.get('extensions')) or info.get('texCoord',0)!=0
            if unsupported and policy=='preserve_source':raise ValueError('asset_source_material_requires_another_capture_backend')
    meshes = load_source(source)
    basis=None;name="brick_full";zone=3;material_info={"metallic":0.,"transmission":0.,"ior":1.5,"roughness_origin":"source_factor"}
    if asset_profile is None:
        perm, scale, center = frame_for_brick(meshes, length_m)
        frame_info={"policy":"legacy_brick_axis_heuristic","semantic_frame_verified":False}
    else:
        basis=proper_rotation(asset_profile["source_to_lie"])
        scale=float(asset_profile["meters_per_source_unit"])
        center=np.asarray(asset_profile["source_pivot"],dtype=float)
        if not np.isfinite(scale) or scale<=0 or center.shape!=(3,) or not np.isfinite(center).all():raise ValueError("asset_units_or_pivot")
        name=asset_profile["master"];zone=asset_profile["material_zone"]
        if not isinstance(name,str) or not name or type(zone) is not int or not 0<=zone<2**24:raise ValueError("asset_master_or_material_zone")
        material_info=optical_profile(asset_profile["optical_material"])
        if material_info['metallic']!=0 or material_info['transmission']!=0:raise ValueError('asset_capture_backend_requires_opaque_nonmetal')
        perm=np.arange(3)
        frame_info={"policy":"authored_semantic_frame","semantic_frame_verified":True,"source_to_lie":basis.tolist(),"meters_per_source_unit":scale,"source_pivot":center.tolist()}

    surface_areas = np.asarray([m.area for m in meshes], dtype=np.float64)
    size_lo = np.min(np.stack([m.vertices.min(axis=0) for m in meshes]), axis=0)
    size_hi = np.max(np.stack([m.vertices.max(axis=0) for m in meshes]), axis=0)
    true_size = (size_hi - size_lo)[perm] * scale
    if basis is not None:
        transformed=np.concatenate([(np.asarray(m.vertices)-center)@basis.T*scale for m in meshes]);bounds_center=(transformed.min(0)+transformed.max(0))*.5;true_size=np.ptp(transformed,axis=0)
    else:bounds_center=np.zeros(3)

    envelope_size = (true_size + .003 * 2).tolist()
    samples = []
    ranges = []
    reports = []
    byte_count = 0
    for lod, target in enumerate(counts):
        rng = np.random.default_rng(seed + 7919 * lod)
        per_mesh = rng.multinomial(target, surface_areas / surface_areas.sum())
        sampled = []
        for mesh, allocated in zip(meshes, per_mesh):
            if not allocated:
                continue
            area_m2 = float(mesh.area) * scale ** 2
            radius = float(np.clip(1.55 * np.sqrt(area_m2 / allocated), .00020, .009))
            sampled.append(_sample_mesh(mesh, int(allocated), rng, perm, scale, center, radius,basis))
        data = np.concatenate(sampled)
        if asset_profile is not None:data[:,8]=zone
        rng.shuffle(data)
        if len(data) != target:
            raise ValueError("Incorrect captured sample count")
        if (np.max(np.abs(data[:, :3]-bounds_center), axis=0).max() > max(true_size) + .02):
            raise ValueError("Sample positions escape source bounds")
        samples.append(data)
        ranges.append({"start": byte_count // STRIDE, "count": int(target)})
        reports.append({"lod": lod, "samples": target,
                        "normal_directions": {
                            k: int(np.count_nonzero(np.argmax(np.abs(data[:, 4:7]), axis=1) == a) and
                                   np.count_nonzero(data[:, 4 + a] * sign > .5))
                            for a, axis in enumerate("xyz") for sign, k in ((1, "+" + axis), (-1, "-" + axis))
                        }})
        byte_count += data.nbytes
    raw = b"".join(array.tobytes(order="C") for array in samples)
    if len(raw) > MAX_BANK_BYTES:
        raise ValueError("64 MiB immutable GPU bank cap exceeded")
    bank_sha = hashlib.sha256(raw).hexdigest()
    metadata = {
        "schema": 1, "stride": STRIDE, "sample_count": sum(counts),
        "bytes": len(raw), "sha256": bank_sha,
        "masters": {name: {"levels": ranges, "bounds_size": envelope_size,
                                   "origin_offset": [0., 0., 0.],"bounds_center":bounds_center.tolist(),
                                   "collision_proxy": "one invisible BoxShape3D"}},
        "source_title": identity["title"], "source_author": identity["author"],
        "source_url": identity["source_url"], "license": identity["license"],
        "source_capture_kind_declared": identity["capture_kind"],
        "source_sha256": source_sha, "expected_source_sha_verified": bool(expected),
        "source_original_triangles": int(sum(len(m.faces) for m in meshes)),
        "source_original_vertices": int(sum(len(m.vertices) for m in meshes)),
        "source_mesh_drawn": False, "source_3d_shape_used": True,
        "source_photo_texture_uv_used": all("lie_vertex_colors_linear" not in m.metadata for m in meshes),
        "source_vertex_colors_used": any("lie_vertex_colors_linear" in m.metadata for m in meshes),
        "source_color_representation": ("glTF COLOR_0 linear vertex RGB" if any("lie_vertex_colors_linear" in m.metadata for m in meshes) else "UV image texture sRGB"),
        "brick_measurement_m": length_m,
        "source_bbox_m": [float(x) for x in true_size], "envelope_size_m": envelope_size,
        "permutation_source_to_lie": [int(x) for x in perm],
        "collision_proxy_count_per_active_brick": 1,
        "not_certified_photogrammetry_just_by_import": True,
        "hero_quality_accepted": False,
        "photo_reference_ab_test_passed": False,
        "lod_reports": reports,
    }
    metadata['asset_frame']=frame_info
    metadata['optical_material']=material_info
    metadata['source_material_policy']='legacy_declared_clay' if asset_profile is None else asset_profile.get('source_material_policy','preserve_source')
    contract=inspect_bank(raw,metadata)
    output.mkdir(parents=True, exist_ok=True)
    (output/"asset-contract.json").write_text(json.dumps(contract,indent=2)+"\n")
    (output / "library.bin").write_bytes(raw)
    (output / "catalog.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print("LIE-BRICK02:" if asset_profile is None else "LIE-ASSET:", metadata["source_original_triangles"], "source triangles;",
          sum(counts), "captured LIE samples;", bank_sha, flush=True)
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--provenance", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] /
                        "gpu_compute/captures/liebrick02")
    parser.add_argument("--length-m", type=float, default=.2032)
    parser.add_argument("--hero", type=int, default=DEFAULT_COUNTS[0])
    parser.add_argument("--middle", type=int, default=DEFAULT_COUNTS[1])
    parser.add_argument("--far", type=int, default=DEFAULT_COUNTS[2])
    parser.add_argument("--seed", type=int, default=2102)
    args = parser.parse_args()
    capture(args.source, args.provenance, args.output, args.length_m,
            (args.hero, args.middle, args.far), args.seed)


if __name__ == "__main__":
    main()
