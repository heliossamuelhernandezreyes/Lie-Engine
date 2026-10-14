"""Source-preserving LIE-WALL04 indirect visibility on 96 ACTUAL brick envelopes.

The legacy factor matrix used a SINGLE huge global wall core for all 872
patches. This incorrectly blocks exterior light bounced around individual
bricks, leaving the photographed wall unnaturally black. Replace ONLY WALL04
factor visibility (not radiometry, patch positions, photons or source XYZ)
with physically grounded original 96 light-only scanned-brick AABBs.
"""
from __future__ import annotations
import argparse,hashlib,json,zlib
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
DEFAULT=ROOT/"gpu_compute/assets/lie_wall04"
RESTORE=ROOT/"gpu_compute/captures/liewall04"
PATCHES=872
BRICKS=96

def calculate(light:dict, wall:dict, shadow_planes=None) ->tuple[np.ndarray,dict]:
    patches=light["patches"]
    boxes=np.asarray(light["direct_shadow_boxes"],dtype=np.float64)
    n=len(patches)
    if n!=PATCHES or boxes.shape!=(BRICKS,2,3):
        raise ValueError("Unexpected real LIE11 patch topology or brick count")
    if (wall["collision"]["spatial_envelope_count"]!=1 or
        wall["wall_layout"]["brick_count"]!=BRICKS or
        wall["lighting"]["node_count"]!=PATCHES or
        wall["original_meshes_drawn"]):
        raise ValueError("Brick scan geometry, lighting, or single invisible box changed")
    if light.get("factor_normalization")!="symmetric_local":
        raise ValueError("Unsupported original LIE11 factor normalization")

    center=np.asarray([p["position"] for p in patches],np.float64)
    normal=np.asarray([p["normal"] for p in patches],np.float64)
    area=np.asarray([p["area"] for p in patches],np.float64)
    if np.min(area)<=0 or not np.isfinite(center).all() or not np.isfinite(normal).all():
        raise ValueError("Invalid original source patches")

    # The original immutable 9-patch codes map groups of 9 -> each of the
    # 96 separate scanned bricks. Mortar nodes 864..871 have NO brick owner.
    owner=np.where(np.arange(n)<BRICKS*9,np.arange(n)//9,-1).astype(np.int16)
    factors=np.zeros((n,n),np.float64)
    geometrically_facing=0
    rejected_by_other_bricks=0
    cross_brick_unoccluded=0

    for i in range(n-1):
        ids=np.arange(i+1,n,dtype=np.int32)
        delta=center[ids]-center[i]
        d2=np.einsum("ij,ij->i",delta,delta)
        dist=np.sqrt(np.maximum(d2,1e-16))
        direction=delta/dist[:,None]
        cos_a=np.maximum(direction@normal[i],0.0)
        cos_b=np.maximum(-np.einsum("ij,ij->i",direction,normal[ids]),0.0)
        valid=(d2>1e-10)&(cos_a>1e-10)&(cos_b>1e-10)
        # Do not pass an indirect photon THROUGH one indivisible source
        # brick between its back/side/front patches; those paths are internal.
        valid &= (owner[i]!=owner[ids]) | (owner[i]<0)
        geometrically_facing+=int(valid.sum())
        if not np.any(valid):continue
        was_eligible=valid.copy()

        # World-space AABB ray visibility. The emitting/receiving parent
        # brick does not cast a shadow over its OWN source patch at t≈0/1;
        # all 94 other brick bodies retain exact scanned-layout occlusion.
        for k in range(BRICKS):
            if owner[i]==k:continue
            possible=valid&(owner[ids]!=k)
            if not np.any(possible):continue
            lo=np.full(len(ids),.001,dtype=np.float64)
            hi=np.full(len(ids),.999,dtype=np.float64)
            for axis in range(3):
                d=delta[:,axis]
                p=center[i,axis]
                a,b=boxes[k,0,axis],boxes[k,1,axis]
                parallel=np.abs(d)<1e-8
                if p<a or p>b:
                    possible &= ~parallel
                safe=np.where(parallel,1.,d)
                near=(a-p)/safe
                far=(b-p)/safe
                lo=np.maximum(lo,np.minimum(near,far))
                hi=np.minimum(hi,np.maximum(near,far))
                possible &= (hi>=lo)
                if not np.any(possible):break
            if shadow_planes is not None and np.any(possible):
                plane=np.asarray(shadow_planes[k],dtype=np.float64)
                side=float(center[i]@plane[:3]-plane[3]);rate=delta@plane[:3]
                parallel=np.abs(rate)<1e-9
                possible &= ~(parallel & (side>0))
                safe=np.where(parallel,1.,rate);cross=-side/safe
                hi=np.where(rate>1e-9,np.minimum(hi,cross),hi)
                lo=np.where(rate<-1e-9,np.maximum(lo,cross),lo)
                possible &= hi>=lo
            valid[possible]=False
            if not np.any(valid):break
        rejected_by_other_bricks+=int((was_eligible&~valid).sum())
        cross_brick_unoccluded+=int(valid.sum())
        if np.any(valid):
            weight=cos_a[valid]*cos_b[valid]/(np.pi*d2[valid])
            j=ids[valid]
            factors[i,j]=area[j]*weight
            factors[j,i]=area[i]*weight

    rows=factors.sum(axis=1)
    caps=np.maximum(1.,np.maximum(rows[:,None],rows[None,:]))
    factors/=caps
    if not np.isfinite(factors).all() or np.min(factors)<0:
        raise ValueError("Invalid physically grounded WALL04 transport weights")
    # Energy-conserving normalized factor budget.
    out=factors.astype("<f4",copy=False)
    report={"schema":"lie-wall04-scanned-per-brick-indirect-visibility/1",
        "patches":n,"light_only_brick_boxes":BRICKS,
        "input_wall_sha256":wall["sha256"],
        "input_source_scan_sha256":wall["source_scan_sha256"],
        "input_light_sha256":wall["lighting"]["sha256"],
        "source_triangle_geometry_rendered":0,
        "collision_spatial_envelopes":1,
        "factor_normalization":light["factor_normalization"],
        "global_opaque_core_used_for_direct_rays":False,
        "global_opaque_core_used_for_indirect_factors":False,
        "indirect_occluders":"96 original source-aligned light-only scanned brick bounds, excluding endpoint parents",
        "facing_patch_pairs":geometrically_facing,
        "blocked_by_other_bricks":rejected_by_other_bricks,
        "unoccluded_indirect_pairs":cross_brick_unoccluded,
        "energy_row_sum_max":float(out.sum(axis=1).max()),
        "min_factor":float(out.min()),"max_factor":float(out.max()),
        "light_sources_added":0,"original_brick_samples_changed":False,"scan_front_plane_clipping":shadow_planes is not None,
        "limitation":"AABB source-aligned brick volume is an approximation to an irregular scanned outline",
        "accepted_photoreal_quality":False,
        "bytes":out.nbytes,
        "sha256":hashlib.sha256(out.tobytes()).hexdigest()}
    return out,report


def bake(wall_dir:Path=DEFAULT,restore:Path=RESTORE)->dict:
    wall=json.loads((wall_dir/"catalog.json").read_text(encoding="utf-8"))
    p=wall_dir/"light-model.json"
    raw=p.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=wall["lighting"]["sha256"]:
        raise ValueError("Original immutable LIE11 light patches SHA mismatch")
    data,manifest=calculate(json.loads(raw),wall)
    wall_dir.mkdir(parents=True,exist_ok=True)
    (wall_dir/"indirect_factors.zlib").write_bytes(zlib.compress(data.tobytes(),6))
    (wall_dir/"indirect_factors.json").write_text(json.dumps(manifest,indent=2)+"\n")
    restore.mkdir(parents=True,exist_ok=True)
    (restore/"indirect_factors.bin").write_bytes(data.tobytes())
    return manifest


def verify(wall_dir:Path=DEFAULT,restore:Path=RESTORE)->dict:
    report=json.loads((wall_dir/"indirect_factors.json").read_text())
    raw=zlib.decompress((wall_dir/"indirect_factors.zlib").read_bytes())
    assert report["patches"]==PATCHES and report["light_only_brick_boxes"]==BRICKS
    assert report["bytes"]==len(raw)==PATCHES*PATCHES*4
    assert report["sha256"]==hashlib.sha256(raw).hexdigest()
    assert report["collision_spatial_envelopes"]==1
    assert report["original_brick_samples_changed"] is False
    out=restore/"indirect_factors.bin"
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_bytes(raw)
    return report


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wall-dir",type=Path,default=DEFAULT)
    parser.add_argument("--restore-dir",type=Path,default=RESTORE)
    parser.add_argument("--verify",action="store_true")
    args=parser.parse_args()
    print(json.dumps(verify(args.wall_dir,args.restore_dir) if args.verify
                     else bake(args.wall_dir,args.restore_dir),indent=2))
