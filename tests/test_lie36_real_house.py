"""Independent authenticity, aperture, layout and resource-budget checks for LIE36."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
import sys

import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from lie36_real_house import original_samples,build,aperture,plan,BUDGETS

class TestRealHouse(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        cls.dest=Path(cls.temp.name)
        cls.catalog, cls.layout=build(cls.dest)
        cls.source,_=original_samples()
        cls.masters=np.frombuffer((cls.dest/"library.bin").read_bytes(),dtype="<f4").reshape(-1,20)
        cls.ids=np.fromfile(cls.dest/"source-ids.bin",dtype="<u4")
    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()
    def test_all_nonoptical_data_from_real_capture(self):
        self.assertEqual(len(self.ids),len(self.masters))
        # Radius and sample face footprint legitimately change; NOT XYZ,
        # normal, roughness, RGB, material, attributes or genuine source ID.
        original=self.source[self.ids]
        cols=[0,1,2,4,5,6,7,8,9,10,11,12,13,14,15]
        np.testing.assert_array_equal(self.masters[:,cols],original[:,cols])
        self.assertGreater(np.count_nonzero(self.masters[:,9]>=864),100)
        self.assertGreater(np.count_nonzero(self.masters[:,9]<864),100)
    def test_sha_and_catalog(self):
        raw=(self.dest/"library.bin").read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),self.catalog["sha256"])
        self.assertEqual(hashlib.sha256((self.dest/"source-ids.bin").read_bytes()).hexdigest(),self.catalog["source_reference_sha256"])
        self.assertEqual(len(raw),self.catalog["sample_count"]*80)
        self.assertEqual(self.catalog["source_bank_sha256"],"f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da")
        self.assertFalse(self.catalog["original_mesh_drawn"])
    def test_openings_are_physically_absent(self):
        for k in ["brick","window","door","slit"]:
            for lod,level in enumerate(self.catalog["masters"][k]["levels"]):
                samples=self.masters[level["start"]:level["start"]+level["count"]]
                self.assertEqual(len(samples),BUDGETS[lod])
                self.assertTrue(aperture(k,samples).all(),k)
        self.assertLess(np.count_nonzero(np.abs(self.masters[self.catalog["masters"]["door"]["levels"][0]["start"]:self.catalog["masters"]["door"]["levels"][0]["start"]+BUDGETS[0],0])<.52),1)
    def test_real_two_storey_l_building_budget(self):
        p=plan()
        self.assertEqual(len(p["footprint_cells"]),5)
        self.assertEqual(p["stories"],2)
        self.assertEqual(p["edges"],10)
        self.assertLessEqual(len(p["instances"]),128)
        self.assertLessEqual(len(p["instances"])*BUDGETS[0],750000)
        self.assertGreater(len(p["instances"]),100)
        self.assertEqual(len([x for x in p["instances"] if x["group"]=="roof"]),20)
        self.assertEqual(len([x for x in p["instances"] if x["master"]=="door"]),3)
        self.assertGreater(len([x for x in p["instances"] if x["master"]=="window"]),8)

if __name__=="__main__":unittest.main()
