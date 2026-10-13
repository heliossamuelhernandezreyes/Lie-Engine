"""Require an explicit source-aligned mask for every unreviewed photographic PBR crop.

Original color, 16-bit height, normal GL, roughness and AO remain unmodified.
The RGBA preview is only for auditing source-mortar candidates, NOT a complete
certified mortar texture nor source of brick pixels for runtime.
"""
from __future__ import annotations
import argparse,json
from pathlib import Path
import numpy as np
from PIL import Image


def produce(derived: Path) -> dict:
    report=json.loads((derived/"mortar-unreviewed-report.json").read_text())
    if report.get("certified_mortar_only") or report.get("human_mask_reviewed"):
        raise ValueError("Expected G1-pending photographed source candidates")
    with Image.open(derived/"mortar-unreviewed-mask.png") as image:
        mask=image.convert("L").copy()
    source_w,source_h=report["source_dimensions"]
    preview_w,preview_h=mask.size
    if [preview_w,preview_h]!=report["preview_dimensions"]:
        raise ValueError("Preview dimensions mismatched")
    if source_w/preview_w!=source_h/preview_h:
        raise ValueError("Nonuniform source/preview pixel registration")
    result=[]
    for i,record in enumerate(report["candidate_crops"]):
        x0,y0,x1,y1=record["source_bbox_xyxy"]
        if x1<=x0 or y1<=y0: raise ValueError("Invalid source crop")
        box=(x0/source_w*preview_w,y0/source_h*preview_h,
             x1/source_w*preview_w,y1/source_h*preview_h)
        # Explicit original-world pixel mapping, never independently
        # guessed UV offsets for individual PBR channels.
        tile=mask.transform((x1-x0,y1-y0),Image.Transform.EXTENT,box,
                            resample=Image.Resampling.NEAREST)
        v=np.asarray(tile)
        count=int(np.count_nonzero(v>127))
        fraction=count/v.size
        if count==0 or fraction>.90:
            raise ValueError("Mask empty or encompasses almost entire donor brick")
        stem=f"candidate-{i:02d}"
        tile.save(derived/f"{stem}-pixel-mask.png")
        with Image.open(derived/record["source_files"]["color"]) as image:
            color=image.convert("RGBA")
        if color.size!=tile.size:
            raise ValueError("Misregistered PBR color crop")
        color.putalpha(tile)
        color.save(derived/f"{stem}-mortar-only-preview.png")
        result.append({"index":i,"source_bbox_xyxy":record["source_bbox_xyxy"],
                       "mask":f"{stem}-pixel-mask.png",
                       "masked_color_preview":f"{stem}-mortar-only-preview.png",
                       "candidate_pixel_count":count,
                       "candidate_fraction":round(float(fraction),5),
                       "status":"unreviewed_mortar_candidate_only"})
    data={"schema":"lie-mortar01-masked-crops/1.0",
          "material_id":report["material_id"],"source_sha256":report["source_sha256"],
          "source_resolution":report["source_resolution"],
          "mask_interpolation":"nearest_source_pixel_registered_preview",
          "physical_height_scale_verified":False,"hero_quality_accepted":False,
          "source_brick_pixels_eligible_for_bank":False,
          "g1_human_review_passed":False,"candidates":result}
    (derived/"mortar-unreviewed-masked-crops.json").write_text(json.dumps(data,indent=2)+"\n")
    return data


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory",required=True,type=Path)
    args=parser.parse_args()
    report=produce(args.directory)
    print("Masked",len(report["candidates"]),"original photographed PBR candidate regions; G1 pending")
