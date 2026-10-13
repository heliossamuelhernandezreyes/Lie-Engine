"""LIE-WALL02: source-measured front micro-nodes and 96 noncolliding shadow proxies."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import lie_wall01_bake as wall


def ray_hits_box(source: np.ndarray,target: np.ndarray,low: np.ndarray,high: np.ndarray) -> bool:
    diff=target-source
    lo,hi=.001,.999
    for axis in range(3):
        if abs(diff[axis])<1e-8:
            if source[axis]<low[axis] or source[axis]>high[axis]:
                return False
        else:
            u=(low[axis]-source[axis])/diff[axis]
            v=(high[axis]-source[axis])/diff[axis]
            lo=max(lo,min(u,v));hi=min(hi,max(u,v))
    return lo<=hi


class RealScanMicroLightTest(unittest.TestCase):
    def test_nine_real_source_regions(self):
        self.assertEqual(wall.NODES_PER_BRICK,9)
        _,bank=wall.load_scan()
        s=bank[:220000]
        patches=wall.micro_patch_indices(s)
        self.assertEqual(sorted(set(patches.tolist())),list(range(9)))
        counts=np.bincount(patches,minlength=9)
        self.assertGreater(int(counts.min()),50)
        front=patches>=5
        self.assertGreater(int(front.sum()),20000)
        for quadrant in range(5,9):
            sampled=s[patches==quadrant]
            self.assertGreater(float(np.std(sampled[:,0])),.005)
            self.assertGreater(float(np.std(sampled[:,12:15])),.005)

    def test_exact_wall_and_node_mapping_with_real_glb_source(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)
            result=wall.build(destination=out)
            model=json.loads((out/"light-model.json").read_text())
            source=json.loads((ROOT/"gpu_compute/assets/lie_brick02/catalog.json").read_text())
            raw=(out/"library.bin").read_bytes()
            self.assertEqual(result["source_scan_sha256"],source["source_sha256"])
            self.assertEqual(result["wall_layout"]["brick_count"],96)
            self.assertEqual(result["lighting"]["node_count"],865)
            self.assertEqual(result["lighting"]["nodes_per_brick"],9)
            self.assertEqual(result["lighting"]["direct_shadow_occluders"],96)
            self.assertEqual(result["collision"]["spatial_envelope_count"],1)
            self.assertFalse(result["original_meshes_drawn"])
            self.assertEqual(len(raw),result["sample_count"]*80)
            self.assertEqual(hashlib.sha256(raw).hexdigest(),result["sha256"])
            self.assertEqual(len(model["patches"]),865)
            self.assertEqual(len(model["direct_shadow_boxes"]),96)
            self.assertEqual(model["direct_shadow_nodes_per_brick"],9)
            self.assertEqual(model["direct_shadow_mortar_node"],864)
            self.assertEqual(model["factor_normalization"],"symmetric_local")
            self.assertEqual(model["bounces"],2)
            samples=np.frombuffer(raw,dtype="<f4").reshape((-1,20))
            self.assertTrue(np.isfinite(samples).all())
            self.assertGreater(float(np.std(samples[:,12:15])),.01)
            self.assertTrue(np.all((samples[:,9]>=0)&(samples[:,9]<865)))
            hero=result["masters"]["real_scan_wall"]["levels"][0]
            values=samples[hero["start"]:hero["start"]+hero["count"]]
            for cell in range(4):
                count=int(np.count_nonzero(values[:,9]==5+cell))
                self.assertGreater(count,150)
            self.assertEqual(int(np.count_nonzero(values[:,9]==864)),hero["count"]-384000)
            size=np.asarray(result["masters"]["real_scan_wall"]["bounds_size"])
            self.assertGreater(float(size[0]),2.4)
            self.assertLess(float(size[2]),.2)
            for patch in model["patches"]:
                n=np.asarray(patch["normal"])
                self.assertAlmostEqual(float(np.dot(n,n)),1.,places=5)
                self.assertGreater(patch["area"],0)
                self.assertGreaterEqual(patch["gray_mean"],0)
                self.assertLessEqual(patch["gray_mean"],1)

            # The new direct visibility proxies are not colliders or source meshes.
            # Their lines of sight are tested with the same deterministic slab
            # intersection as the optional GPU LIE11 stage-0 path.
            bybrick=model["patches"]
            boxes=model["direct_shadow_boxes"]
            self.assertEqual(len(boxes),96)
            seen=0
            for idx,p in enumerate(bybrick[:864]):
                a=np.asarray(p["position"],dtype=float)
                lights=np.asarray([-1.75,.9,.28],dtype=float)
                for j,b in enumerate(boxes):
                    if j==idx//9:continue
                    if ray_hits_box(a,lights,np.asarray(b[0]),np.asarray(b[1])):
                        seen+=1
                        break
            self.assertGreater(seen,5,seen)

            from lie_light_transport import validate,solve
            validate(model)
            energy=solve(model,bounces=2)
            self.assertLessEqual(energy["max_row_sum"],1.+1e-7)
            self.assertGreater(sum(sum(row) for row in energy["irradiance"]),0)
            for gen in energy["energy_by_generation"]:
                for out_power,in_power in zip(gen["outgoing"],gen["incoming"]):
                    self.assertLessEqual(out_power,in_power+1e-7)
            print("LIE-WALL02: 865 source-derived light nodes; 96 ray occluders; energy conservative")


if __name__=="__main__":
    unittest.main()
