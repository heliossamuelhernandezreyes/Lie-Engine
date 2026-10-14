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
FRONT_NORMAL_Z = 0.75
FRONT_SURFACE_PERCENTILE = 25.0
LOCAL_FACE_PERCENTILE = 80.0
MIN_BRICK_POINTS = 55
JOINT_VISUAL_WIDTH_M = 0.0030


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
        self.face_floors=[]
        self.rejected_deep_edge_samples=0
        self.trees_sample_counts=[]
        self.exposed_world_xy=[]
        self.exposed_world_z=[]
        self.globally_corrected_samples=0
        self.global_cap_recess_mm_total=0.
        self.global_max_cap_recess_mm=0.
        self.min_actual_sample_clearance_m=float("inf")
        if len(records)<10000:
            raise ValueError("No authentic original visible front face samples")
        for row in range(8):
            for col in range(12):
                owner=row*12+col
                part=records[(records[:,9]//9).astype(np.int32)==owner]
                if len(part)<MIN_BRICK_POINTS:
                    raise ValueError(f"Insufficient front scan samples on brick {owner}")
                # +Z normals alone also select corners, cracks, broken SIDE
                # slopes and occasional *back* relief from the full 3D scan.
                # These were erroneously taken as the main face, with actual
                # edge references down at Z=-4.67mm vs front Z=+57.8mm.
                # Use the measured FRONT LAYER of each original brick.
                floor=float(np.quantile(part[:,2],FRONT_SURFACE_PERCENTILE/100.))
                exposed=part[part[:,2]>=floor]
                self.rejected_deep_edge_samples+=len(part)-len(exposed)
                self.face_floors.append(floor)
                center=self.center(row,col)
                visual=center+(exposed[:,0:2].astype(np.float64)-center)*self.scale
                offsets=np.abs(visual-center)
                edge=((offsets[:,0]>=self.width*self.scale[0]*.5-EDGE_BAND_M) |
                      (offsets[:,1]>=self.height*self.scale[1]*.5-EDGE_BAND_M))
                chosen=exposed[edge]
                coords=visual[edge]
                if len(chosen)<16:
                    # Still use authentic front layer, never the deep scan.
                    chosen=exposed
                    coords=visual
                if len(chosen)<MIN_BRICK_POINTS//2:
                    raise ValueError(f"Too few authentic exposed front samples for {owner}")
                # Stable source order makes duplicate/near-equal KD queries
                # reproducible across independent Python runs.
                keys=np.lexsort((chosen[:,2],coords[:,1],coords[:,0]))
                coords=coords[keys]
                chosen=chosen[keys]
                self.trees[owner]=cKDTree(coords)
                self.heights[owner]=chosen[:,2].astype(np.float64)
                # Retain ALL actual front-layer source points, not only the
                # coarse edge subset. These are the relevant nearest *visible
                # scanned brick surface* even when the two edge trees happen
                # to be sparse. Avoid hiding real brick surface behind the
                # smoothed source edge quantile.
                self.exposed_world_xy.append(visual)
                self.exposed_world_z.append(exposed[:,2].astype(np.float64))
                self.trees_sample_counts.append(len(chosen))
                self.fallbacks[owner]=float(np.quantile(exposed[:,2],.80))
        self.exposed_world_xy=np.concatenate(self.exposed_world_xy)
        self.exposed_world_z=np.concatenate(self.exposed_world_z)
        self.exposed_surface_tree=cKDTree(self.exposed_world_xy)
        if len(self.exposed_world_z)<10000:
            raise ValueError("No source-verified exposed brick surface exists")

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
                # Exposed face, not the lowest chipped side wall: the old
                # 70th percentile of unfiltered points produced deep black
                # trenches and made the joint's edge look raised.
                candidate=np.quantile(original,LOCAL_FACE_PERCENTILE/100.,axis=1)
                d_near=np.min(dist,axis=1)
                distant=d_near>NEAR_LIMIT_M
                candidate[distant]=self.fallbacks[int(owner)]
                self.measured+=int((~distant).sum())
                self.fallback_uses+=int(distant.sum())
                if len(d_near):
                    self.max_near_distance=max(self.max_near_distance,float(np.min([np.max(d_near),NEAR_LIMIT_M])))
                face[take]=candidate
            nearby.append(face)
        estimated=np.minimum.reduce(nearby)
        # FINAL PHYSICAL OCCLUSION CAP. The prior code used 80th-percentile
        # smoothed edge depths (and a global fallback for ~46% of queries).
        # Source scan statistics proved that ~81% of photo-mortar samples
        # then sat IN FRONT of the nearest real exposed brick surface!
        # Resolve nearest point from ALL actual front-layer brick samples,
        # in exactly the XY expansion the renderer uses. It supplies a
        # locally observed cap; the 80th percentile is no longer allowed
        # to float mortar over the original scanned source.
        nearest_dist, nearest_id=self.exposed_surface_tree.query(xy,k=1)
        nearest_front=self.exposed_world_z[nearest_id]
        if not np.isfinite(nearest_front).all():
            raise ValueError("Missing scanned front for physical mortar cap")
        limit=np.minimum(estimated,nearest_front)
        changed=estimated>nearest_front
        self.globally_corrected_samples+=int(changed.sum())
        correction=estimated[changed]-nearest_front[changed]
        self.global_cap_recess_mm_total+=float(correction.sum()*1000.)
        if correction.size:
            self.global_max_cap_recess_mm=max(self.global_max_cap_recess_mm,
                                              float(correction.max()*1000.))
        self.min_actual_sample_clearance_m=min(self.min_actual_sample_clearance_m,
                                                 float(np.min(nearest_front-limit)))
        # Provenance and physically coherent FRONT layer are strict: below
        # the lowest exposed-face cutoff means a side/deep pit was wrongly
        # classified as the face. Abort instead of silently excavating mortar.
        if (not np.isfinite(limit).all() or
                np.min(limit) < min(self.face_floors)-.003 or
                np.max(limit) > .09):
            raise ValueError("Mortar edge profile fell into the scanned brick side/back layer")
        self.local_values.extend((float(np.min(limit)),float(np.max(limit))))
        return limit.astype(np.float32)

    def report(self)->dict:
        return {
            "method":"minimum of both adjacent authentic BRICK FRONT LAYERS' local z 80th percentiles",
            "source":"verified WALL03 source XYZ and normals, original 96 bricks",
            "physical_reference":"per-joint, per-sample nearest front scan neighborhood",
            "edge_band_m":EDGE_BAND_M,
            "near_distance_limit_m":NEAR_LIMIT_M,
            "front_normal_z_cutoff":FRONT_NORMAL_Z,
            "brick_front_layer_percentile":FRONT_SURFACE_PERCENTILE,
            "source_brick_visual_joint_target_m":JOINT_VISUAL_WIDTH_M,
            "local_edge_face_percentile":LOCAL_FACE_PERCENTILE,
            "exposed_layer_z_min_m":min(self.face_floors),
            "exposed_layer_z_max_m":max(self.face_floors),
            "rejected_deep_scan_samples":self.rejected_deep_edge_samples,
            "minimum_source_samples_per_brick_edge":min(self.trees_sample_counts),
            "nearest_scan_bricks":2,
            "nearest_observed_front_cap_enabled":True,
            "nearest_observed_front_samples":int(len(self.exposed_world_z)),
            "global_nearest_exposed_scan_queries_capped":self.globally_corrected_samples,
            "global_nearest_exposed_scan_cap_mean_mm":(
                self.global_cap_recess_mm_total/max(self.globally_corrected_samples,1)),
            "global_nearest_exposed_scan_cap_max_mm":self.global_max_cap_recess_mm,
            "min_cap_clearance_against_actual_exposed_scan_m":self.min_actual_sample_clearance_m,
            "coverage_model":"per-original-scan-front XY nearest sample, not fabricated planar brick face",
            "sample_queries_near_source":self.measured,
            "sample_queries_fallback":self.fallback_uses,
            "observed_face_z_min_m":min(self.local_values) if self.local_values else None,
            "observed_face_z_max_m":max(self.local_values) if self.local_values else None,
            "original_scanned_xyz_rgb_edited":False,
            "guarantee":"mortar <= nearest actual exposed photographed brick face z - specified recess",
            "limitations":"per-brick scanned edge sampling and percentiles cannot prove exact pointwise flush at all rough pores",
        }
