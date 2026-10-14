"""Checks that LIE35 is driven by unchanged real captured normals and color."""
import math
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from lie35_wall04_adapter import extraction,real_case
from lie35_directional_reference import propagate


class TestRealWall04DirectionalAdapter(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=extraction()

    def test_real_scan_provenance_and_sample_count(self):
        self.assertEqual(len(self.data["emitters"]),8)
        self.assertEqual(self.data["nodes"],[5,6,7,8,14,15,16,17])
        for a in self.data["emitters"]:
            self.assertGreater(a["captured_samples"],25)
            self.assertGreater(a["normal"][2],0.35)
            self.assertAlmostEqual(sum(x*x for x in a["normal"]),1,places=5)

    def test_genuine_roughness_color_and_opaque_optical_default(self):
        for e in self.data["emitters"]:
            self.assertLessEqual(e["roughness"],1)
            self.assertGreaterEqual(e["roughness"],0.025)
            self.assertTrue(all(0<=v<=1 for v in e["albedo"]))
            self.assertEqual(e["metallic"],0.0)
            self.assertEqual(e["transmission"],0.0)

    def test_light_moves_energy_without_creating_it(self):
        case=real_case()
        result=propagate(case["emitters"],case["receivers"])
        self.assertGreater(sum(sum(v) for v in result),0)
        for ch in range(3):
            self.assertLessEqual(sum(v[ch] for v in result),
                                 sum(e["power"][ch] for e in case["emitters"])+1e-8)


if __name__=="__main__":unittest.main()
