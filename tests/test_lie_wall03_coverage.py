"""LIE-WALL-03: immutable authentic brick pixels, 8 mortar light regions, one envelope."""
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
import lie_wall01_bake as base
import lie_wall03_bake as wall


class Wall03GeometryMaterialCodes(unittest.TestCase):
    def test_source_and_mortar_are_distinct(self):
        self.assertEqual(wall.MORTAR_FIRST,864)
        self.assertEqual(wall.MORTAR_NODES,8)
        source,samples=base.load_scan()
        self.assertEqual(source["source_original_triangles"],500000)
        self.assertTrue(source["source_vertex_colors_used"])
        self.assertEqual(len(samples),281000)

    def test_mortar_replacement_does_not_erase_original_scan(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            old=root/"wall02"
            new=root/"wall03"
            meta_old=base.build(destination=old)
            meta=wall.build(destination=new)
            old_data=np.frombuffer((old/"library.bin").read_bytes(),dtype="<f4").reshape(-1,20)
            new_data=np.frombuffer((new/"library.bin").read_bytes(),dtype="<f4").reshape(-1,20)
            is_clay=old_data[:,9]<864
            self.assertEqual(int(is_clay.sum()),96*(4000+1300+240))
            self.assertTrue(np.array_equal(old_data[is_clay],new_data[is_clay]))
            self.assertEqual(meta["sample_count"],meta_old["sample_count"])
            self.assertEqual(meta["lighting"]["node_count"],872)
            self.assertEqual(meta["lighting"]["mortar_nodes"],8)
            self.assertEqual(meta["lighting"]["nodes_per_brick"],9)
            self.assertEqual(meta["collision"]["spatial_envelope_count"],1)
            self.assertEqual(meta["wall_layout"]["mortar_recess_m"],.0035)
            self.assertFalse(meta["original_meshes_drawn"])
            self.assertFalse(meta["hero_quality_accepted"])
            self.assertEqual(meta["source_scan_sha256"],meta_old["source_scan_sha256"])
            self.assertEqual(meta["source_master_sha256"],meta_old["source_master_sha256"])
            self.assertTrue(np.isfinite(new_data).all())
            self.assertEqual(meta["bytes"],len(new_data)*80)
            self.assertEqual(meta["sha256"],hashlib.sha256((new/"library.bin").read_bytes()).hexdigest())
            self.assertGreaterEqual(new_data[:,9].min(),0)
            self.assertLessEqual(new_data[:,9].max(),871)
            ids=np.unique(new_data[~is_clay,9]).astype(int).tolist()
            self.assertEqual(ids,list(range(864,872)))
            self.assertTrue(np.all(new_data[~is_clay,2]>old_data[~is_clay,2]))
            model_bytes=(new/"light-model.json").read_bytes()
            self.assertEqual(hashlib.sha256(model_bytes).hexdigest(),meta["lighting"]["sha256"])
            model=json.loads(model_bytes)
            self.assertEqual(len(model["patches"]),872)
            self.assertEqual(len(model["direct_shadow_boxes"]),96)
            self.assertEqual(model["direct_shadow_mortar_node"],864)
            self.assertEqual(model["direct_shadow_mortar_count"],8)
            self.assertEqual([p["mortar_course"] for p in model["patches"][864:]],list(range(8)))
            self.assertTrue(all(p["material"]=="mortar" for p in model["patches"][864:]))
            from lie_light_transport import validate,solve
            validate(model)
            solve_result=solve(model,bounces=2)
            self.assertLessEqual(solve_result["max_row_sum"],1.0000001)
            for g in solve_result["energy_by_generation"]:
                for emitted,received in zip(g["outgoing"],g["incoming"]):
                    self.assertLessEqual(emitted,received+1e-7)
            print("LIE-WALL03: authentic scanned brick bytes unchanged; 872 valid light codes; conservative.")

    def test_no_unlimited_image_inpainting(self):
        shader=(ROOT/"gpu_compute/shaders/lie_wall03_coverage.glsl").read_text()
        self.assertIn("if(stage==8)",shader)
        self.assertIn("if(x==0 && y==0)continue;",shader)
        self.assertIn("group!=chosen_group",shader)
        self.assertIn("chosen_group=node<864u?node/9u:96u",shader)
        self.assertIn("n>=3 && ((left && right) || (up && down))",shader)
        self.assertIn("dot(normalize(pr.normal.xyz),chosen_normal)<.65",shader)
        self.assertIn("imageLoad(injected_node_irradiance",shader)
        self.assertNotIn("texture2D(",shader)


if __name__=="__main__":
    unittest.main()
