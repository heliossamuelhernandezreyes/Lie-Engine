"""Compose source-authentic LIE-WALL03 bricks with experimental real-photo mortar.

Old procedural mortar is removed, never the CC-BY 96-brick source records.
All mortar source bytes are from a separately SHA-locked 8K CC0 donor;
unreviewed provenance is explicit and must not pass hero-quality gates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zlib
import numpy as np
from lie_sparse_transport import pack as pack_sparse_factors

ROOT = Path(__file__).resolve().parents[1]
OLD_DIR = ROOT/"gpu_compute/assets/lie_wall03"
MORTAR_DIR = ROOT/"gpu_compute/assets/lie_mortar01"
DEST = ROOT/"gpu_compute/assets/lie_wall04"


def read_bank(directory: Path, name: str, cat: dict) -> np.ndarray:
    raw=zlib.decompress((directory/name).read_bytes())
    if (len(raw)!=cat["bytes"] or len(raw)!=cat["sample_count"]*80 or
        hashlib.sha256(raw).hexdigest()!=cat["sha256"]):
        raise ValueError("Broken source photo or original scan SHA256: "+str(directory))
    return np.frombuffer(raw,dtype="<f4").reshape((-1,20))


def compose(old: Path=OLD_DIR,mortar: Path=MORTAR_DIR,dest: Path=DEST) -> dict:
    base=json.loads((old/"catalog.json").read_text())
    source=json.loads((mortar/"catalog.json").read_text())
    if (base["wall_layout"]["brick_count"]!=96 or
        base["collision"]["spatial_envelope_count"]!=1 or
        base["lighting"]["node_count"]!=872 or
        base["sha256"]!=source["brick_source_wall03_sha256"] or
        not source["workshop_only_not_renderer_accepted"] or
        source["photographic_joint_masks_reviewed"] or
        base["original_meshes_drawn"]):
        raise ValueError("WALL04 must be experimental and preserve original source contracts")
    bricks=read_bank(old,"wall_bank.zlib",base)
    joint=read_bank(mortar,"mortar-bank.zlib",source)
    old_levels=base["masters"]["real_scan_wall"]["levels"]
    new_levels=source["levels"]
    if len(old_levels)!=3 or len(new_levels)!=3:
        raise ValueError("Expected three source and mortar LODs")
    levels=[]
    packed=[]
    offset=0
    brick_hashes=[]
    for i,(old_lod,new_lod) in enumerate(zip(old_levels,new_levels)):
        orig=bricks[old_lod["start"]:old_lod["start"]+old_lod["count"]]
        scanned=orig[orig[:,9]<864]  # exact float32 bits copied, never recolored
        legacy=orig[orig[:,9]>=864]
        if len(scanned)!=96*(4000,1300,240)[i] or not len(legacy):
            raise ValueError("Historical brick/mortar record partition changed")
        incoming=joint[new_lod["start"]:new_lod["start"]+new_lod["count"]]
        if not len(incoming) or np.any((incoming[:,9]<864)|(incoming[:,9]>871)):
            raise ValueError("Invalid independently coded photographed mortar samples")
        copy=np.concatenate((scanned,incoming)).astype("<f4",copy=False)
        if len(copy)>=750000 or not np.isfinite(copy).all():
            raise ValueError("LIE-WALL04 compositor work cap or NaN exceeded")
        verify=copy[:len(scanned)].tobytes()
        expected=hashlib.sha256(scanned.tobytes()).hexdigest()
        if hashlib.sha256(verify).hexdigest()!=expected:
            raise ValueError("Scanned source brick bytes were modified")
        brick_hashes.append(expected)
        levels.append({"start":offset,"count":len(copy),
                       "scanned_original_brick_samples":len(scanned),
                       "captured_mortar_samples":len(incoming)})
        offset+=len(copy)
        packed.append(copy)
    raw=np.concatenate(packed).astype("<f4",copy=False).tobytes()
    new=json.loads(json.dumps(base))
    new["sample_count"]=offset
    new["bytes"]=len(raw)
    new["sha256"]=hashlib.sha256(raw).hexdigest()
    new["masters"]["real_scan_wall"]["levels"]=levels
    new["wall_layout"]["procedural_recessed_mortar"]=False
    new["wall_layout"]["mortar_samples_per_lod"]=[v["captured_mortar_samples"] for v in levels]
    new["lighting"]["gpu_joint_coverage"]="captured_mortar_xyz_samples_no_shader_flat_joint_fallback"
    new["wall04"]={
        "version":"LIE-WALL-04 experimental real-photo mortar samples",
        "original_brick_record_sha256_by_lod":brick_hashes,
        "wall03_original_sha256":base["sha256"],
        "mortar01_sha256":source["sha256"],
        "mortar01_cc0_source_maps":source["source_sha256"],
        "local_brick_edge_recess_profile": source["flush_mortar_experiment"],
        "mortar_front_calibration": "local two-adjacent-brick scanned XYZ, not global plane",
        "min_mortar_edge_recess_m": source["flush_mortar_experiment"]["min_recess_from_local_brick_edge_m"],
        "mortar_source_masks_reviewed":False,
        "mortar_source_height_absolute_mm_verified":False,
        "product_quality_accepted":False,
        "legacy_mortar_samples_removed":True,
        "original_brick_samples_byte_identical":True,
        "source_triangles_rendered":0,
        "total_spatial_envelopes":1,
        "sha256_of_original_LIE11_light_model":base["lighting"]["sha256"]
    }
    new["hero_quality_accepted"]=False
    new["note"]="WALL04 EXPERIMENTAL: photographic G1 masks still unreviewed; native GPU not proven by authoring bank."
    if new["collision"]["spatial_envelope_count"]!=1 or new["source_original_triangles"]!=500000:
        raise ValueError("Loss of original one-box or actual source identity")
    light=(old/"light-model.json").read_bytes()
    if hashlib.sha256(light).hexdigest()!=new["lighting"]["sha256"]:
        raise ValueError("Original LIE11 RGB patches modified")
    dest.mkdir(parents=True,exist_ok=True)
    (dest/"wall_bank.zlib").write_bytes(zlib.compress(raw,6))
    (dest/"catalog.json").write_text(json.dumps(new,indent=2)+"\n",encoding="utf-8")
    (dest/"light-model.json").write_bytes(light)
    return new


def restore(source: Path=DEST,dest: Path=ROOT/"gpu_compute/captures/liewall04") -> dict:
    catalog=json.loads((source/"catalog.json").read_text())
    raw=zlib.decompress((source/"wall_bank.zlib").read_bytes())
    light=(source/"light-model.json").read_bytes()
    if len(raw)!=catalog["bytes"] or hashlib.sha256(raw).hexdigest()!=catalog["sha256"]:
        raise ValueError("WALL04 immutable combined sample bank checksum mismatch")
    if hashlib.sha256(light).hexdigest()!=catalog["lighting"]["sha256"]:
        raise ValueError("LIE11 872-node light-code SHA changed")
    assert catalog["collision"]["spatial_envelope_count"]==1
    assert catalog["wall04"]["original_brick_samples_byte_identical"]
    dest.mkdir(parents=True,exist_ok=True)
    (dest/"library.bin").write_bytes(raw)
    (dest/"catalog.json").write_text(json.dumps(catalog,indent=2)+"\n")
    (dest/"light-model.json").write_bytes(light)
    # Recover the exact 872 x 872 indirect LIE11 transfer from the scanned
    # source. No synthetic/zero-factor fallback is permitted.
    locked=source/"indirect_factors.json"
    packed=source/"indirect_factors.zlib"
    if locked.exists() or packed.exists():
        if not locked.is_file() or not packed.is_file():
            raise ValueError("Incomplete scanned 96-brick indirect visibility bank")
        proof=json.loads(locked.read_text())
        factors=zlib.decompress(packed.read_bytes())
        if (len(factors)!=872*872*4 or len(factors)!=proof["bytes"] or
            hashlib.sha256(factors).hexdigest()!=proof["sha256"] or
            proof["input_light_sha256"]!=catalog["lighting"]["sha256"] or
            proof["input_wall_sha256"]!=catalog["sha256"] or
            proof["light_only_brick_boxes"]!=96 or
            proof["collision_spatial_envelopes"]!=1):
            raise ValueError("Original LIE11 matrix provenance failed")
        (dest/"indirect_factors.bin").write_bytes(factors)
        (dest/"indirect_factors.json").write_text(json.dumps(proof,indent=2)+"\n")
        sparse, sparse_meta = pack_sparse_factors(factors,872)
        sparse_meta["source_factor_sha256"] = proof["sha256"]
        sparse_meta["input_wall_sha256"] = catalog["sha256"]
        sparse_meta["input_light_sha256"] = catalog["lighting"]["sha256"]
        (dest/"indirect_sparse.bin").write_bytes(sparse)
        (dest/"indirect_sparse.json").write_text(json.dumps(sparse_meta,indent=2)+"\n")
    return catalog


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wall03",type=Path,default=OLD_DIR)
    parser.add_argument("--mortar",type=Path,default=MORTAR_DIR)
    parser.add_argument("--output",type=Path,default=DEST)
    parser.add_argument("--restore",action="store_true")
    args=parser.parse_args()
    result=(restore(args.output) if args.restore else compose(args.wall03,args.mortar,args.output))
    print(json.dumps({"sha256":result["sha256"],"samples":result["sample_count"],
                      "lods":result["masters"]["real_scan_wall"]["levels"],
                      "single_invisible_box":result["collision"]["spatial_envelope_count"],
                      "unreviewed":not result["wall04"]["mortar_source_masks_reviewed"]},indent=2))
