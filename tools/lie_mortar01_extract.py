"""LIE-MORTAR-01: conservative photographic mortar candidates, never procedural texture.

Produces UNREVIEWED mask, source-aligned PBR crops and a report. G1 requires
human review before any visual sample bank or WALL04 renderer integration.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, median_filter, maximum_filter1d
from scipy.signal import find_peaks
from lie_mortar01_acquire import MATERIAL, REQUIRED, inspect_lock


class UncertainSegmentation(ValueError):
    """Source has insufficient reliably detected joints."""


def _preview(path: Path, target_width: int) -> tuple[np.ndarray, tuple[int,int]]:
    with Image.open(path) as im:
        wh=im.size
        scale=min(1., target_width / wh[0])
        size=(round(wh[0]*scale),round(wh[1]*scale))
        if im.mode in ("I;16","I","F"):
            im=im.convert("F")
        elif im.mode not in ("L","RGB","RGBA"):
            im=im.convert("RGB")
        return np.asarray(im.resize(size,Image.Resampling.BILINEAR)).copy(),wh


def _normalized_height(v: np.ndarray) -> np.ndarray:
    if v.ndim==3: v=v[:,:,0]
    data=v.astype(np.float32)
    if not np.isfinite(data).all(): raise UncertainSegmentation("Nonfinite displacement")
    a,b=np.percentile(data,[2,98])
    if b<=a+1e-7: raise UncertainSegmentation("No displacement contrast")
    return np.clip((data-a)/(b-a),0,1)


def _peaks(data: np.ndarray, distance: int, prominence: float) -> np.ndarray:
    values=gaussian_filter(data.astype(np.float32),1.25)
    peaks,properties=find_peaks(values,distance=distance,prominence=prominence)
    if len(peaks)>30:
        peaks=peaks[np.argsort(properties["prominences"])[-30:]]
    return np.sort(peaks)


def detect(height: np.ndarray, min_row_spacing: int = 15) -> dict:
    if height.ndim!=2 or min(height.shape)<128:
        raise ValueError("Expected 2D displacement preview with dimensions >= 128")
    H,W=height.shape
    smooth=gaussian_filter(height.astype(np.float32),1.25)
    horizontal=np.maximum(maximum_filter1d(smooth,size=21,axis=0)-smooth,0)
    vertical=np.maximum(maximum_filter1d(smooth,size=21,axis=1)-smooth,0)
    hp=np.quantile(horizontal,.64,axis=1)
    rows=_peaks(hp,max(min_row_spacing,H//32),max(.018,float(hp.std())*.75))
    rows=[int(y) for y in rows if hp[y]>max(.022,float(np.percentile(hp,60)))]
    if len(rows)<2: raise UncertainSegmentation("No credible photographed horizontal joints")
    mask=np.zeros((H,W),np.uint8)
    features=[]
    wy=max(2,round(H/180))
    wx=max(2,round(W/180))
    for i,y in enumerate(rows):
        lo,hi=max(0,y-wy),min(H,y+wy+1)
        # Follow local troughs: measured source isn't an ideal straight grid.
        line=lo+np.argmax(horizontal[lo:hi],axis=0)
        line=median_filter(line.astype(np.int32),size=17)
        xx=np.arange(W)
        evidence=horizontal[line,xx]
        good=evidence>max(.016,float(np.percentile(hp[rows],35))*.32)
        good[:8]=False;good[-8:]=False
        for off in (-1,0,1):
            yy=line+off
            ok=good & (yy>=2) & (yy<H-2)
            mask[yy[ok],xx[ok]]=255
        features.append({"kind":"horizontal","row":i,"center_preview_y":y,
                         "coverage":round(float(good.mean()),4)})
    bounds=[0]+[round((a+b)/2) for a,b in zip(rows[:-1],rows[1:])]+[H]
    verticals=0
    for course,(start,end) in enumerate(zip(bounds[:-1],bounds[1:])):
        y0,y1=start+2,end-2
        if y1-y0<12: continue
        profile=np.quantile(vertical[y0:y1],.65,axis=0)
        cols=_peaks(profile,max(12,W//42),max(.02,float(profile.std())*.75))
        cols=[int(x) for x in cols if profile[x]>max(.028,float(np.percentile(profile,60)))]
        for x in cols:
            lo,hi=max(0,x-wx),min(W,x+wx+1)
            line=lo+np.argmax(vertical[y0:y1,lo:hi],axis=1)
            line=median_filter(line.astype(np.int32),size=11)
            yy=np.arange(y0,y1)
            good=vertical[yy,line]>max(.023,float(profile[x])*.30)
            for off in (-1,0,1):
                xx=line+off
                ok=good & (xx>=2) & (xx<W-2)
                mask[yy[ok],xx[ok]]=255
            cov=float(good.mean())
            if cov>.25:
                features.append({"kind":"vertical","course":course,
                    "center_preview_x":x,"preview_y_range":[y0,y1],
                    "coverage":round(cov,4)})
                verticals+=1
    occupancy=float(np.mean(mask>0))
    if not .001<occupancy<.2 or verticals<2:
        raise UncertainSegmentation("G1 blocked: mortar evidence too weak or broad")
    return {"mask":mask,"features":features,"rows":rows,
            "vertical_count":verticals,"coverage_fraction":round(occupancy,5)}


def extract(root: Path=MATERIAL, preview_width: int=1024, max_crops: int=12) -> dict:
    lock=inspect_lock(root)
    source=root/"source"
    derived=root/"derived"
    derived.mkdir(parents=True,exist_ok=True)
    locate=lambda key: source/lock["files"][key]["filename"]
    height_img,dimensions=_preview(locate("height"),preview_width)
    color,color_dimensions=_preview(locate("color"),preview_width)
    if color_dimensions!=dimensions:
        raise UncertainSegmentation("Source color and displacement dimensions differ")
    height=_normalized_height(height_img)
    detected=detect(height)
    mask=detected["mask"]
    rgb=np.repeat(color[:,:,None],3,axis=2) if color.ndim==2 else color[:,:,:3]
    rgb=rgb.astype(np.uint8)
    overlay=rgb.copy()
    active=mask>0
    overlay[active]=(np.array([220,35,55],np.float32)*.75+rgb[active]*.25).astype(np.uint8)
    Image.fromarray(overlay).save(derived/"mortar-unreviewed-overlay.png")
    Image.fromarray(mask).save(derived/"mortar-unreviewed-mask.png")
    original_w,original_h=dimensions
    small_h,small_w=mask.shape
    candidates=[]
    ranked=sorted(detected["features"],key=lambda item:item["coverage"],reverse=True)
    for i,feature in enumerate(ranked[:max_crops]):
        if feature["kind"]=="horizontal":
            y=feature["center_preview_y"]
            x0,x1=round(small_w*.25),round(small_w*.75)
            y0,y1=max(0,y-5),min(small_h,y+6)
        else:
            x=feature["center_preview_x"]
            x0,x1=max(0,x-5),min(small_w,x+6)
            y0,y1=feature["preview_y_range"]
        box=(int(x0*original_w/small_w),int(y0*original_h/small_h),
             int(x1*original_w/small_w),int(y1*original_h/small_h))
        if box[2]<=box[0] or box[3]<=box[1]: continue
        files={}
        for channel in (*REQUIRED,"ao"):
            if channel not in lock["files"]: continue
            filename=f"candidate-{i:02d}-{channel}.png"
            with Image.open(locate(channel)) as image:
                image.crop(box).save(derived/filename)
            files[channel]=filename
        candidates.append({"source_bbox_xyxy":list(box),"kind":feature["kind"],
                           "source_files":files,"status":"unreviewed"})
    report={"schema":"lie-mortar01-extraction/1.0","material_id":lock["material_id"],
            "source_resolution":lock["resolution"],"source_dimensions":list(dimensions),
            "source_sha256":{k:v["sha256"] for k,v in lock["files"].items()},
            "preview_dimensions":[small_w,small_h],
            "absolute_displacement_mm_verified":False,"human_mask_reviewed":False,
            "certified_mortar_only":False,
            "candidate_mortar_fraction":detected["coverage_fraction"],
            "detected_horizontal_rows":len(detected["rows"]),
            "detected_vertical_segments":detected["vertical_count"],
            "features":detected["features"],"candidate_crops":candidates,
            "next_gate":"Human inspection: reject brick contamination; NO LIE bank before approval"}
    (derived/"mortar-unreviewed-report.json").write_text(json.dumps(report,indent=2)+"\n")
    return report


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,default=MATERIAL)
    parser.add_argument("--preview-width",type=int,default=1024)
    parser.add_argument("--max-crops",type=int,default=12)
    args=parser.parse_args()
    if not 512<=args.preview_width<=2048 or not 1<=args.max_crops<=32:
        parser.error("preview-width 512..2048, max-crops 1..32")
    report=extract(args.root,args.preview_width,args.max_crops)
    print(json.dumps({k:v for k,v in report.items()
        if k not in ("features","candidate_crops")},indent=2))


if __name__=="__main__":main()
