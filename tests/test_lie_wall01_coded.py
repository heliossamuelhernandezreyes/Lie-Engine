"""LIE-WALL-01 geometry and coded irradiance invariants; real source mandatory."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import lie_wall01_bake as wall

class RealScannedWallTest(unittest.TestCase):
    def test_layout_has_one_containing_envelope_and_stagger(self):
        scan=np.array([.2032,.0774222599,.119617167],dtype=np.float32)
        b,foot=wall.layout(scan)
        self.assertEqual(len(b),96)
        self.assertEqual(len({i["node_start"] for i in b}),96)
        self.assertEqual(b[0]["node_start"],0)
        self.assertEqual(b[-1]["node_start"],570)
        pitch=float(scan[0])+.0085
        self.assertAlmostEqual(float(b[12]["center"][0]-b[0]["center"][0]),pitch*.5,places=5)
        self.assertGreater(float(foot[0]),2.4)

    def test_scan_face_orientation(self):
        normals=np.array([[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]],dtype=np.float32)
        self.assertEqual(wall.face_indices(normals).tolist(),list(range(6)))

    def test_real_source_bank_and_light_nodes(self):
        catalog, samples=wall.load_scan()
        self.assertTrue(catalog["source_vertex_colors_used"])
        self.assertEqual(catalog["source_original_triangles"],500000)
        self.assertEqual(samples.shape[0],281000)
        self.assertGreater(float(np.std(samples[:,12:15])),.025)
        self.assertFalse(catalog["hero_quality_accepted"])

    def test_build_wall_master_from_real_source(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            destination=Path(directory)
            meta=wall.build(destination=destination)
            raw=(destination/"library.bin").read_bytes()
            codes=(destination/"light-model.json").read_bytes()
            self.assertEqual(meta["source_original_triangles"],500000)
            self.assertEqual(meta["source_master_sha256"],wall.load_scan()[0]["sha256"])
            self.assertEqual(len(raw),meta["sample_count"]*80)
            self.assertEqual(hashlib.sha256(raw).hexdigest(),meta["sha256"])
            self.assertEqual(hashlib.sha256(codes).hexdigest(),meta["lighting"]["sha256"])
            self.assertEqual(meta["wall_layout"]["brick_count"],96)
            self.assertEqual(meta["collision"]["spatial_envelope_count"],1)
            self.assertFalse(meta["original_meshes_drawn"])
            self.assertEqual(meta["lighting"]["node_count"],577)
            levels=meta["masters"]["real_scan_wall"]["levels"]
            self.assertEqual([l["count"] for l in levels],[410000,130000,24340])
            values=np.frombuffer(raw,dtype="<f4").reshape((-1,20))
            self.assertTrue(np.isfinite(values).all())
            self.assertTrue(np.all(values[:,9]>=0))
            self.assertTrue(np.all(values[:,9]<577))
            for lod in levels:
                level=values[lod["start"]:lod["start"]+lod["count"]]
                self.assertEqual(int((level[:,9]==576).sum()),(260*100,130*40,65*20)[levels.index(lod)])
            bbox=np.asarray(meta["masters"]["real_scan_wall"]["bounds_size"])
            self.assertGreater(float(bbox[0]),2.4)
            model=json.loads(codes)
            self.assertEqual(len(model["patches"]),577)
            self.assertEqual(len(model["lights"]),1)
            self.assertEqual(model["factor_normalization"],"symmetric_local")
            self.assertEqual(model["bounces"],2)
            from lie_light_transport import validate,solve
            validate(model)
            oracle=solve(model,bounces=2)
            self.assertLessEqual(oracle["max_row_sum"],1.0000001)
            self.assertGreater(sum(sum(v) for v in oracle["irradiance"]),0)
            for entry in oracle["energy_by_generation"]:
                for a,b in zip(entry["outgoing"],entry["incoming"]):
                    self.assertLessEqual(a,b+1e-7)
            print("LIE-WALL01 CPU reference: energy conservative; 577 material nodes")

if __name__=="__main__":
    unittest.main()
