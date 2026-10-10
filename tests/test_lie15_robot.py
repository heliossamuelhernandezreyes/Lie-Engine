import base64,hashlib,json,math,sys,unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lie15_robot import skeleton,normal_world,blocked
class RobotContract(unittest.TestCase):
    def test_scaled_normal_is_perpendicular_to_surface(self):
        s=skeleton(.8)[3]; tangent=np.array(s['basis'][1]); normal=normal_world([1,0,0],s)
        self.assertAlmostEqual(float(tangent@normal),0,places=12)
        self.assertAlmostEqual(np.linalg.norm(normal),1,places=12)
    def test_articulations_attach_without_skin_deformation(self):
        for phase in [0,.5,2,5]:
            parts=skeleton(phase)
            self.assertEqual(len(parts),15)
            for upper,lower in [(3,4),(5,6),(7,8),(10,11)]:
                endpoint=np.array(parts[upper]['pivot'])-np.array(parts[upper]['rotation'][1])*parts[upper]['scale'][1]
                np.testing.assert_allclose(endpoint,parts[lower]['pivot'],atol=1e-12)
    def test_oriented_box_visibility(self):
        s=skeleton()[0]
        self.assertTrue(blocked([-2,.55,0],[2,.55,0],[s]))
        self.assertFalse(blocked([-2,3,0],[2,3,0],[s]))
    def test_source_bytes_are_actual_traced_asset(self):
        p=Path(__file__).resolve().parents[1]/'gpu_compute/assets/lie15'; d=json.loads((p/'provenance.json').read_text())
        data=base64.b64decode((p/'box-small.glb.base64').read_text(),validate=False)
        self.assertEqual(data[:4],b'glTF'); self.assertEqual(hashlib.sha256(data).hexdigest(),d['source_glb_sha256']); self.assertEqual(d['license'],'CC0-1.0')
    def test_invalid_pose(self):
        with self.assertRaises(ValueError): skeleton(float('nan'))
