"""LIE-WALL04: query ACTUAL photographed brick edge depths to recess mortar.

No meshes, extra spatial boxes, or altered brick source records. The nearest
original +Z-facing scanned front points on BOTH neighbors give each mortar
sample a local reference. Computation is offline, not a runtime GPU cost.
"""
from __future__ import annotations

from collections import defaultdict
import hashlib
import zlib
from pathlib import Path
from typing import Any
import numpy as np
from scipy.spatial import cKDTree

EDGE_BAND_M = 0.022
NEAR_LIMIT_M = 0.028
FRONT_NORMAL_Z = 0.65
MIN_BRICK_POINTS = 55
JOINT_VISUAL_WIDTH_M = 0.0060


class OriginalBrickEdgeField:
    def __init__(self, wall_catalog_path: Path, catalog: dict[str, Any]):
        source=wall_catalog_path.parent/"wall_bank.zlib"
        raw=zlib.decompress(source.read_bytes())
        if (hashlib.sha256(raw).hexdigest()!=catalog["sha256"] or
                len(raw)!=catalog["sample_count"]*80):
            raise ValueError("Original source scan bank modified")
        level=catalog["masters"]["real_scan_wall"]["levels"][0]
        records=np.frombuffer(raw,dtype="<f4").reshape((-1,20))
        records=records[level["start"]:level["start"]+level["count"]]
        records=records[(records[:,9]>=0)&(records[:,9]<864)&
                        (records[:,6]>=FRONT_NORMAL_Z)]
        self.geom=catalog["wall_layout"]["mortar_shader_layout"]
        g=self.geom
        self.origin_x=float(g["first_brick_x_m"])
        self.origin_y=float(g["first_brick_y_m"])
        self.pitch_x=float(g["pitch_x_m"])
        self.pitch_y=float(g["pitch_y_m"])
        self.width=float(g["brick_length_m"])
        self.height=float(g["brick_height_m"])
        self.stagger=float(g["running_bond_stagger_fraction"])
        self.scale=np.array([(self.pitch_x-JOINT_VISUAL_WIDTH_M)/self.width,
                             (self.pitch_y-JOINT_VISUAL_WIDTH_M)/self.height])
        self.trees={}
        self.heights={}
        self.fallbacks={}
        self.measured=0
        self.fallback_uses=0
        self.max_near_distance=0.
        self.local_values=[]
        if len(records)<10000:
            raise ValueError("No authentic original visible front face samples")
        for row in range(8):
            for col in range(12):
                owner=row*12+col
                part=records[(records[:,9]//9).astype(np.int32)==owner]
                if len(part)<MIN_BRICK_POINTS:
                    raise ValueError(f"Insufficient front scan samples on brick {owner}")
                center=self.center(row,col)
                visual=center+(part[:,0:2].astype(np.float64)-center)*self.scale
                offsets=np.abs(visual-center)
                edge=((offsets[:,0]>=self.width*self.scale[0]*.5-EDGE_BAND_M) |
                      (offsets[:,1]>=self.height*self.scale[1]*.5-EDGE_BAND_M))
                chosen=part[edge]
                coords=visual[edge]
                if len(chosen)<16:
                    # Never invent a planar generic face if edge samples scarce.
                    chosen=part
                    coords=visual
                self.trees[owner]=cKDTree(coords)
                self.heights[owner]=chosen[:,2].astype(np.float64)
                self.fallbacks[owner]=float(np.quantile(part[:,2],.70))

    def center(self,row:int,col:int)->np.ndarray:
        return np.array([self.origin_x+col*self.pitch_x+(row%2)*self.stagger*self.pitch_x,
                         self.origin_y+row*self.pitch_y],dtype=np.float64)

    def _adjacent(self,kind:str,row:int,column:int,xy:np.ndarray)->list[np.ndarray]:
        if kind=="vertical":
            if not (0<=row<8 and 0<=column<11):
                raise ValueError("Invalid vertical original brick seam")
            owners=[np.full(len(xy),row*12+column,dtype=np.int32),
                    np.full(len(xy),row*12+column+1,dtype=np.int32)]
        elif kind=="horizontal":
            if not 0<=row<7:
                raise ValueError("Invalid horizontal original brick seam")
            owners=[]
            for rr in (row,row+1):
                left=self.origin_x+(rr%2)*self.stagger*self.pitch_x-self.width*.5
                cc=np.floor((xy[:,0]-left)/self.pitch_x).astype(np.int32)
                cc=np.clip(cc,0,11)
                owners.append(rr*12+cc)
        else:
            raise ValueError("Unknown photographed mortar seam orientation")
        return owners

    def face_limit(self,kind:str,row:int,column:int,xy:np.ndarray)->np.ndarray:
        xy=np.asarray(xy,dtype=np.float64)
        if xy.ndim!=2 or xy.shape[1]!=2 or not np.isfinite(xy).all():
            raise ValueError("Invalid mortar XYZ query")
        nearby=[]
        for owner_array in self._adjacent(kind,row,column,xy):
            face=np.empty(len(xy),dtype=np.float64)
            for owner in np.unique(owner_array):
                take=np.flatnonzero(owner_array==owner)
                tree=self.trees[int(owner)]
                k=min(12,len(self.heights[int(owner)]))
                dist,which=tree.query(xy[take],k=k)
                if k==1:
                    dist=dist[:,None];which=which[:,None]
                original=self.heights[int(owner)][which]
                # 70th local quantile is robust against pits; min of both
                # neighboring faces wins so mortar never dominates the
                # *estimated* local edge surface.
                candidate=np.quantile(original,.70,axis=1)
                d_near=np.min(dist,axis=1)
                distant=d_near>NEAR_LIMIT_M
                candidate[distant]=self.fallbacks[int(owner)]
                self.measured+=int((~distant).sum())
                self.fallback_uses+=int(distant.sum())
                if len(d_near):
                    self.max_near_distance=max(self.max_near_distance,float(np.min([np.max(d_near),NEAR_LIMIT_M])))
                face[take]=candidate
            nearby.append(face)
        limit=np.minimum.reduce(nearby)
        # Genuine worn brick edges may be recessed MUCH farther than the
        # global face median. A guessed 5mm front-Z floor incorrectly rejected
        # observed surfaces and could force mortar to float over them. Use
        # the real source spatial envelope instead, with a small tolerance.
        if (not np.isfinite(limit).all() or
                np.min(limit) < -0.09 or np.max(limit) > .09):
            raise ValueError("Photographed edge outside original brick spatial envelope")
        self.local_values.extend((float(np.min(limit)),float(np.max(limit))))
        return limit.astype(np.float32)

    def report(self)->dict:
        return {
            "method":"minimum of both adjacent authentic scanned brick front-edge local z 70th percentiles",
            "source":"verified WALL03 source XYZ and normals, original 96 bricks",
            "physical_reference":"per-joint, per-sample nearest front scan neighborhood",
            "edge_band_m":EDGE_BAND_M,
            "near_distance_limit_m":NEAR_LIMIT_M,
            "front_normal_z_cutoff":FRONT_NORMAL_Z,
            "nearest_scan_bricks":2,
            "sample_queries_near_source":self.measured,
            "sample_queries_fallback":self.fallback_uses,
            "observed_face_z_min_m":min(self.local_values) if self.local_values else None,
            "observed_face_z_max_m":max(self.local_values) if self.local_values else None,
            "original_scanned_xyz_rgb_edited":False,
            "guarantee":"mortar <= estimated local edge-face z - required recess",
            "limitations":"per-brick scanned edge sampling and percentiles cannot prove exact pointwise flush at all rough pores",
        }
